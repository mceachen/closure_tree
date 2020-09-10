require 'spec_helper'

describe 'Configuration' do
  before(:each) do
    # Make sure we start up with no active connection
    ActiveRecord::Base.connection_pool.release_connection
  end

  it 'returns connection to the pool after has_closure_tree setup' do
    class TypeDuplicate < ActiveRecord::Base
      self.table_name = "namespace_type#{table_name_suffix}"
      has_closure_tree
    end
    expect(ActiveRecord::Base.connection_pool.active_connection?).to be_falsey # +false+ in AR 4, +nil+ in AR 5
  end

  it 'returns connection to the pool after has_closure_tree setup with order' do
    class MetalDuplicate < ActiveRecord::Base
      self.table_name = "#{table_name_prefix}metal#{table_name_suffix}"
      has_closure_tree order: 'sort_order', name_column: 'value'
    end
    expect(ActiveRecord::Base.connection_pool.active_connection?).to be_falsey
  end

  it 'returns connection to the pool after has_closure_tree_root setup' do
    class GroupDuplicate < ActiveRecord::Base
      self.table_name = "#{table_name_prefix}group#{table_name_suffix}"
      has_closure_tree_root :root_user
    end
    expect(ActiveRecord::Base.connection_pool.active_connection?).to be_falsey
  end
end
