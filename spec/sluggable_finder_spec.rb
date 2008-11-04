require File.dirname(__FILE__) + '/spec_helper'

ActiveRecord::Base.establish_connection(
  :adapter=>'sqlite3',
  :dbfile=> File.join(File.dirname(__FILE__),'db','test.db')
)

LOGGER = Logger.new(File.dirname(__FILE__)+'/log/test.log')
ActiveRecord::Base.logger = LOGGER

# A test Model according to test schema in db/test.db
#
class Item < ActiveRecord::Base
  named_scope :published, :conditions => {:published => true}
end

# Simple slug
#
class SimpleItem < Item
  sluggable_finder :title # defaults :to => :slug
end

# Slug from virtual attribute
#
class VirtualItem < Item
  sluggable_finder :some_method
  
  def some_method
    "#{self.class.name} #{title}"
  end
  
end

# This one saves slug into 'permalink' field
#
class PermalinkItem < Item
  sluggable_finder :title, :to => :permalink
end

# A top level object to test scoped slugs
#
class Category < ActiveRecord::Base
  has_many :scoped_items
end

class ScopedItem < Item
  belongs_to :category
  sluggable_finder :title, :scope => :category_id
end

describe SimpleItem, 'encoding permalinks' do
  before(:each) do
    Item.delete_all
    @item = SimpleItem.create!(:title => 'Hello World')
    @item2 = SimpleItem.create(:title => 'Hello World')
  end
  
  it "should connect to test sqlite db" do
    Item.count.should == 2
  end
  
  it "should create unique slugs" do
    @item.slug.should == 'hello-world'
    @item2.slug.should == 'hello-world-2'
  end
  
  it "should define to_param to return slug" do
    @item.to_param.should == 'hello-world'
  end
  
  it "should raise ActiveRecord::RecordNotFound" do
    SimpleItem.create!(:title => 'Hello World')
    lambda {
      SimpleItem.find 'non-existing-slug'
    }.should raise_error(ActiveRecord::RecordNotFound)
  end
  
  it "should find normally by ID" do
    SimpleItem.find(@item.id).should == @item
  end
  
  it "should by ID even if ID is string" do
    SimpleItem.find(@item.id.to_s).should == @item
  end
  
end

describe VirtualItem, 'using virtual fields as permalink source' do
  before(:each) do
    Item.delete_all
    @item = VirtualItem.create!(:title => 'prefixed title')
  end
  
  it "should generate slug from a virtual attribute" do
    @item.to_param.should == 'virtualitem-prefixed-title'
  end
  
  it "should find by slug" do
    VirtualItem.find('virtualitem-prefixed-title').to_param.should == @item.to_param
  end
end

describe PermalinkItem,'writing to custom field' do
  before(:each) do
    Item.delete_all
    @item = PermalinkItem.create! :title => 'Hello World'
  end
  
  it "should create slug in custom field if provided" do
    
    @item.permalink.should == 'hello-world'
    @item.slug.should == nil
  end
end

describe ScopedItem,'scoped to parent object' do
  before(:each) do
    Item.delete_all
    @category1 = Category.create!(:name => 'Category one')
    @category2 = Category.create!(:name => 'Category two')
    # Lets create 3 items with the same title, two of them in the same category
    @item1 = @category1.scoped_items.create!(:title => 'A scoped item',:published => true)
    @item2 = @category1.scoped_items.create!(:title => 'A scoped item', :published => false)
    @item3 = @category2.scoped_items.create!(:title => 'A scoped item')
  end
  
  it "should scope slugs to parent items" do
    @item1.to_param.should == 'a-scoped-item'
    @item2.to_param.should == 'a-scoped-item-2' # because this slug is not available for this category
    @item3.to_param.should == 'a-scoped-item'
  end
  
  it "should include sluggable methods in collections" do
    @category1.scoped_items.respond_to?(:find_with_slug).should == true 
  end
  
  it "should find by scoped slug" do
    item1 = @category1.scoped_items.find('a-scoped-item')
    item1.to_param.should == @item1.to_param
  end
  
  it "should find published one (named scope)" do
    @category1.scoped_items.published.find('a-scoped-item').to_param.should == @item1.to_param
  end
  
  it "should not find unpublished one (named scope)" do
    lambda{
      @category1.scoped_items.published.find('a-scoped-item-2')
    }.should raise_error(ActiveRecord::RecordNotFound)
  end
end

describe SimpleItem, 'with AR named scopes' do
  before(:each) do
    Item.delete_all
    @published_one  = SimpleItem.create! :title => 'published 1',:published => true
    @published_two  = SimpleItem.create! :title => 'published 2',:published => true
    @unpublished    = SimpleItem.create! :title => 'not published',:published => false
  end
  
  it "should find published ones" do
    SimpleItem.published.find('published-1').to_param.should == @published_one.to_param
    SimpleItem.published.find('published-2').to_param.should == @published_two.to_param
  end
  
  it "should not find unpublished ones" do
    lambda {
      SimpleItem.published.find('not-published')
    }.should raise_error(ActiveRecord::RecordNotFound)
  end
end