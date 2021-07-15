module ClosureTree
  module HasClosureTree
    def has_closure_tree(options = {})
      options.assert_valid_keys(
        :parent_column_name,
        :dependent,
        :hierarchy_class_name,
        :hierarchy_table_name,
        :name_column,
        :order,
        :dont_order_roots,
        :numeric_order,
        :touch,
        :with_advisory_lock,
        :database_type
      )

      class_attribute :_ct
      self._ct = ClosureTree::Support.new(self, options)

      # Auto-inject the hierarchy table
      # See https://github.com/patshaughnessy/class_factory/blob/master/lib/class_factory/class_factory.rb
      class_attribute :hierarchy_class
      self.hierarchy_class = _ct.hierarchy_class_for_model

      # tests fail if you include Model before HierarchyMaintenance wtf
      include ClosureTree::HierarchyMaintenance
      include ClosureTree::Model
      include ClosureTree::Finders
      include ClosureTree::HashTree
      include ClosureTree::Digraphs

      include ClosureTree::DeterministicOrdering if _ct.order_option?
      include ClosureTree::NumericDeterministicOrdering if _ct.order_is_numeric?

      connection_pool.release_connection
    rescue StandardError => e
      raise e unless ClosureTree.configuration.database_less
    end

    alias_method :acts_as_tree, :has_closure_tree
  end
end
