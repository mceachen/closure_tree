require 'spec_helper'

RSpec.describe ClosureTree::HierarchyMaintenance do
  describe '.rebuild!' do
    it 'rebuild tree' do
      20.times do |counter|
        Metal.create(:value => "Nitro-#{counter}", parent: Metal.all.sample)
      end
      hierarchy_count = MetalHierarchy.count
      expect(hierarchy_count).to be > (20*2)-1 # shallowest-possible case, where all children use the first root
      MetalHierarchy.delete_all
      Metal.rebuild!
      expect(MetalHierarchy.count).to eq(hierarchy_count)
    end

    it 'rebuild tree with specific child order' do
      parent = Metal.create(value: "Parent")
      Metal.create(value: "name3")
      Metal.create(value: "name1")
      Metal.create(value: "name2")
      expect(parent.children).to receive(:reorder).with({value: :desc}).once.and_call_original
      parent.rebuild!(child_order: {value: :desc})
    end
  end

  describe '.cleanup!' do
    let!(:parent) { Metal.create(:value => "parent metal") }
    let!(:child) { Metal.create(:value => "child metal", parent: parent) }

    before do
      MetalHierarchy.delete_all
      Metal.rebuild!
    end

    context 'when an element is deleted' do
      it 'should delete the child hierarchies' do
        child.delete

        Metal.cleanup!

        expect(MetalHierarchy.where(descendant_id: child.id)).to be_empty
        expect(MetalHierarchy.where(ancestor_id: child.id)).to be_empty
      end

      it 'should not delete the parent hierarchies' do
        child.delete
        Metal.cleanup!
        expect(MetalHierarchy.where(ancestor_id: parent.id).size).to eq 1
      end

      it 'should not delete other hierarchies' do
        other_parent = Metal.create(:value => "other parent metal")
        other_child = Metal.create(:value => "other child metal", parent: other_parent)
        Metal.rebuild!

        child.delete
        Metal.cleanup!

        expect(MetalHierarchy.where(ancestor_id: other_parent.id).size).to eq 2
        expect(MetalHierarchy.where(descendant_id: other_child.id).size).to eq 2
      end
    end
  end
end
