# Closure Tree

### Closure_tree lets your ActiveRecord models act as nodes in a [tree data structure](http://en.wikipedia.org/wiki/Tree_%28data_structure%29)

Common applications include modeling hierarchical data, like tags, threaded comments, page graphs in CMSes,
and tracking user referrals.

[![Join the chat at https://gitter.im/closure_tree/Lobby](https://badges.gitter.im/closure_tree/Lobby.svg)](https://gitter.im/closure_tree/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
[![Build Status](https://api.travis-ci.org/ClosureTree/closure_tree.svg?branch=master)](http://travis-ci.org/ClosureTree/closure_tree)
[![Gem Version](https://badge.fury.io/rb/closure_tree.svg)](https://badge.fury.io/rb/closure_tree)

Dramatically more performant than
[ancestry](https://github.com/stefankroes/ancestry) and
[acts_as_tree](https://github.com/amerine/acts_as_tree), and even more
awesome than [awesome_nested_set](https://github.com/collectiveidea/awesome_nested_set/),
closure_tree has some great features:

* __Best-in-class select performance__:
  * Fetch your whole ancestor lineage in 1 SELECT.
  * Grab all your descendants in 1 SELECT.
  * Get all your siblings in 1 SELECT.
  * Fetch all [descendants as a nested hash](#nested-hashes) in 1 SELECT.
  * [Find a node by ancestry path](#find_or_create_by_path) in 1 SELECT.
* __Best-in-class mutation performance__:
  * 2 SQL INSERTs on node creation
  * 3 SQL INSERT/UPDATEs on node reparenting
* __Support for [concurrency](#concurrency)__ (using [with_advisory_lock](https://github.com/ClosureTree/with_advisory_lock))
* __Tested against ActiveRecord 4.2, 5.0, 5.1, 5.2 and 6.0 with  Ruby 2.5 and 2.6__
* Support for reparenting children (and all their descendants)
* Support for [single-table inheritance (STI)](#sti) within the hierarchy
* ```find_or_create_by_path``` for [building out heterogeneous hierarchies quickly and conveniently](#find_or_create_by_path)
* Support for [deterministic ordering](#deterministic-ordering)
* Support for [preordered](http://en.wikipedia.org/wiki/Tree_traversal#Pre-order) traversal of descendants
* Support for rendering trees in [DOT format](http://en.wikipedia.org/wiki/DOT_(graph_description_language)), using [Graphviz](http://www.graphviz.org/)
* Excellent [test coverage](#testing) in a comprehensive variety of environments

See [Bill Karwin](http://karwin.blogspot.com/)'s excellent
[Models for hierarchical data presentation](http://www.slideshare.net/billkarwin/models-for-hierarchical-data)
for a description of different tree storage algorithms.

## Table of Contents

- [Installation](#installation)
- [Warning](#warning)
- [Usage](#usage)
- [Accessing Data](#accessing-data)
- [Polymorphic hierarchies with STI](#polymorphic-hierarchies-with-sti)
- [Deterministic ordering](#deterministic-ordering)
- [Concurrency](#concurrency)
- [FAQ](#faq)
- [Testing](#testing)
- [Change log](#change-log)

## Installation

Note that closure_tree only supports ActiveRecord 4.2 and later, and has test coverage for MySQL, PostgreSQL, and SQLite.

1.  Add `gem 'closure_tree'` to your Gemfile

2.  Run `bundle install`

3.  Add `has_closure_tree` (or `acts_as_tree`, which is an alias of the same method) to your hierarchical model:

    ```ruby
    class Tag < ActiveRecord::Base
      has_closure_tree
    end

    class AnotherTag < ActiveRecord::Base
      acts_as_tree
    end
    ```

    Make sure you check out the [large number of options](#available-options) that `has_closure_tree` accepts.

    **IMPORTANT: Make sure you add `has_closure_tree` _after_ `attr_accessible` and
    `self.table_name =` lines in your model.**

    If you're already using other hierarchical gems, like `ancestry` or `acts_as_tree`, please refer
    to the [warning section](#warning)!

4.  Add a migration to add a `parent_id` column to the hierarchical model.
    You may want to also [add a column for deterministic ordering of children](#deterministic-ordering), but that's optional.

    ```ruby
    class AddParentIdToTag < ActiveRecord::Migration
      def change
        add_column :tags, :parent_id, :integer
      end
    end
    ```

    The column must be nullable. Root nodes have a `NULL` `parent_id`.

5.  Run `rails g closure_tree:migration tag` (and replace `tag` with your model name)
    to create the closure tree table for your model.

    By default the table name will be the model's table name, followed by
    "_hierarchies". Note that by calling ```has_closure_tree```, a "virtual model" (in this case, ```TagHierarchy```)
    will be created dynamically. You don't need to create it.

6.  Run `rake db:migrate`

7.  If you're migrating from another system where your model already has a
    `parent_id` column, run `Tag.rebuild!` and your
    `tag_hierarchies` table will be truncated and rebuilt.

    If you're starting from scratch you don't need to call `rebuild!`.

NOTE: Run `rails g closure_tree:config` to create an initializer with extra
      configurations. (Optional)

## Warning

As stated above, using multiple hierarchy gems (like `ancestry` or `nested set`) on the same model
will most likely result in pain, suffering, hair loss, tooth decay, heel-related ailments, and gingivitis.
Assume things will break.

## Usage

### Creation

Create a root node:

```ruby
grandparent = Tag.create(name: 'Grandparent')
```

Child nodes are created by appending to the children collection:

```ruby
parent = grandparent.children.create(name: 'Parent')
```

Or by appending to the children collection:

```ruby
child2 = Tag.new(name: 'Second Child')
parent.children << child2
```

Or by calling the "add_child" method:

```ruby
child3 = Tag.new(name: 'Third Child')
parent.add_child child3
```

Or by setting the parent on the child :

```ruby
Tag.create(name: 'Fourth Child', parent: parent)
```

Then:

```ruby
grandparent.self_and_descendants.collect(&:name)
=> ["Grandparent", "Parent", "First Child", "Second Child", "Third Child", "Fourth Child"]

child1.ancestry_path
=> ["Grandparent", "Parent", "First Child"]
```

### find_or_create_by_path

You can `find` as well as `find_or_create` by "ancestry paths".

If you provide an array of strings to these methods, they reference the `name` column in your
model, which can be overridden with the `:name_column` option provided to `has_closure_tree`.

```ruby
child = Tag.find_or_create_by_path(%w[grandparent parent child])
```

As of v5.0.0, `find_or_create_by_path` can also take an array of attribute hashes:

```ruby
child = Tag.find_or_create_by_path([
  {name: 'Grandparent', title: 'Sr.'},
  {name: 'Parent', title: 'Mrs.'},
  {name: 'Child', title: 'Jr.'}
])
```

If you're using STI, The attribute hashes can contain the `sti_name` and things work as expected:

```ruby
child = Label.find_or_create_by_path([
  {type: 'DateLabel', name: '2014'},
  {type: 'DateLabel', name: 'August'},
  {type: 'DateLabel', name: '5'},
  {type: 'EventLabel', name: 'Visit the Getty Center'}
])
```

### Moving nodes around the tree

Nodes can be moved around to other parents, and closure_tree moves the node's descendancy to the
new parent for you:

```ruby
d = Tag.find_or_create_by_path %w[a b c d]
h = Tag.find_or_create_by_path %w[e f g h]
e = h.root
d.add_child(e) # "d.children << e" would work too, of course
h.ancestry_path
=> ["a", "b", "c", "d", "e", "f", "g", "h"]
```

When it is more convenient to simply change the `parent_id` of a node directly (for example, when dealing with a form `<select>`), closure_tree will handle the necessary changes automatically when the record is saved:

```ruby
j = Tag.find 102
j.self_and_ancestor_ids
=> [102, 87, 77]
j.update parent_id: 96
j.self_and_ancestor_ids
=> [102, 96, 95, 78]
```

### Nested hashes

```hash_tree``` provides a method for rendering a subtree as an
ordered nested hash:

```ruby
b = Tag.find_or_create_by_path %w(a b)
a = b.parent
b2 = Tag.find_or_create_by_path %w(a b2)
d1 = b.find_or_create_by_path %w(c1 d1)
c1 = d1.parent
d2 = b.find_or_create_by_path %w(c2 d2)
c2 = d2.parent

Tag.hash_tree
=> {a => {b => {c1 => {d1 => {}}, c2 => {d2 => {}}}, b2 => {}}}

Tag.hash_tree(:limit_depth => 2)
=> {a => {b => {}, b2 => {}}}

b.hash_tree
=> {b => {c1 => {d1 => {}}, c2 => {d2 => {}}}}

b.hash_tree(:limit_depth => 2)
=> {b => {c1 => {}, c2 => {}}}
```

**If your tree is large (or might become so), use :limit_depth.**

Without this option, ```hash_tree``` will load the entire contents of that table into RAM. Your
server may not be happy trying to do this.

HT: [ancestry](https://github.com/stefankroes/ancestry#arrangement) and [elhoyos](https://github.com/ClosureTree/closure_tree/issues/11)

### Eager loading

Since most of closure_tree's methods (e.g. `children`) return regular `ActiveRecord` scopes, you can use the `includes` method for eager loading, e.g.

```ruby
comment.children.includes(:author)
```

However, note that the above approach only eager loads the requested associations for the immediate children of `comment`. If you want to walk through the entire tree, you may still end up making many queries and loading duplicate copies of objects.

In some cases, a viable alternative is the following:

```ruby
comment.self_and_descendants.includes(:author)
```

This would load authors for `comment` and all its descendants in a constant number of queries. However, the return value is an array of `Comment`s, and the tree structure is thus lost, which makes it difficult to walk the tree using elegant recursive algorithms.

A third option is to use `has_closure_tree_root` on the model that is composed by the closure_tree model (e.g. a `Post` may be composed by a tree of `Comment`s). So in `post.rb`, you would do:

```ruby
# app/models/post.rb
has_closure_tree_root :root_comment
```

This gives you a plain `has_one` association (`root_comment`) to the root `Comment` (i.e. that with null `parent_id`).

It also gives you a method called `root_comment_including_tree`, which you can invoke as follows:

```ruby
a_post.root_comment_including_tree(:author)
```

The result of this call will be the root `Comment` with all descendants _and_ associations loaded in a constant number of queries. Inverse associations are also setup on all nodes, so as you walk the tree, calling `children` or `parent` on any node will _not_ trigger any further queries and no duplicate copies of objects are loaded into memory.

The class and foreign key of `root_comment` are assumed to be `Comment` and `post_id`, respectively. These can be overridden in the usual way.

The same caveat stated above with `hash_tree` also applies here: this method will load the entire tree into memory. If the tree is very large, this may be a bad idea, in which case using the eager loading methods above may be preferred.

### Graph visualization

```to_dot_digraph``` is suitable for passing into [Graphviz](http://www.graphviz.org/).

For example, for the above tree, write out the DOT file with ruby:
```ruby
File.open("example.dot", "w") { |f| f.write(Tag.root.to_dot_digraph) }
```
Then, in a shell, ```dot -Tpng example.dot > example.png```, which produces:

![Example tree](https://raw.github.com/ClosureTree/closure_tree/master/img/example.png)

If you want to customize the label value, override the ```#to_digraph_label``` instance method in your model.

Just for kicks, this is the test tree I used for proving that preordered tree traversal was correct:

![Preordered test tree](https://raw.github.com/ClosureTree/closure_tree/master/img/preorder.png)

### Available options

When you include ```has_closure_tree``` in your model, you can provide a hash to override the following defaults:

* ```:parent_column_name``` to override the column name of the parent foreign key in the model's table. This defaults to "parent_id".
* ```:hierarchy_class_name``` to override the hierarchy class name. This defaults to the singular name of the model + "Hierarchy", like ```TagHierarchy```.
* ```:hierarchy_table_name``` to override the hierarchy table name. This defaults to the singular name of the model + "_hierarchies", like ```tag_hierarchies```.
* ```:dependent``` determines what happens when a node is destroyed. Defaults to ```nullify```.
    * ```:nullify``` will simply set the parent column to null. Each child node will be considered a "root" node. This is the default.
    * ```:delete_all``` will delete all descendant nodes (which circumvents the destroy hooks)
    * ```:destroy``` will destroy all descendant nodes (which runs the destroy hooks on each child node)
    * ```nil``` does nothing with descendant nodes
* ```:name_column``` used by #```find_or_create_by_path```, #```find_by_path```, and ```ancestry_path``` instance methods. This is primarily useful if the model only has one required field (like a "tag").
* ```:order``` used to set up [deterministic ordering](#deterministic-ordering)
* ```:touch``` delegates to the `belongs_to` annotation for the parent, so `touch`ing cascades to all children (the performance of this for deep trees isn't currently optimal).

## Accessing Data

### Class methods

* ```Tag.root``` returns an arbitrary root node
* ```Tag.roots``` returns all root nodes
* ```Tag.leaves``` returns all leaf nodes
* ```Tag.hash_tree``` returns an [ordered, nested hash](#nested-hashes) that can be depth-limited.
* ```Tag.find_by_path(path, attributes)``` returns the node whose name path is ```path```. See (#find_or_create_by_path).
* ```Tag.find_or_create_by_path(path, attributes)``` returns the node whose name path is ```path```, and will create the node if it doesn't exist already.See (#find_or_create_by_path).
* ```Tag.find_all_by_generation(generation_level)``` returns the descendant nodes who are ```generation_level``` away from a root. ```Tag.find_all_by_generation(0)``` is equivalent to ```Tag.roots```.
* ```Tag.with_ancestor(ancestors)``` scopes to all descendants whose ancestor is in the given list.
* ```Tag.lowest_common_ancestor(descendants)``` finds the lowest common ancestor of the descendants.
### Instance methods

* ```tag.root``` returns the root for this node
* ```tag.root?``` returns true if this is a root node
* ```tag.root_of?(node)``` returns true if current node is root of another one
* ```tag.child?``` returns true if this is a child node. It has a parent.
* ```tag.leaf?``` returns true if this is a leaf node. It has no children.
* ```tag.leaves``` is scoped to all leaf nodes in self_and_descendants.
* ```tag.depth``` returns the depth, or "generation", for this node in the tree. A root node will have a value of 0.
* ```tag.parent``` returns the node's immediate parent. Root nodes will return nil.
* ```tag.parent_of?(node)``` returns true if current node is parent of another one
* ```tag.children``` is a ```has_many``` of immediate children (just those nodes whose parent is the current node).
* ```tag.child_ids``` is an array of the IDs of the children.
* ```tag.child_of?(node)``` returns true if current node is child of another one
* ```tag.ancestors``` is a ordered scope of [ parent, grandparent, great grandparent, … ]. Note that the size of this array will always equal ```tag.depth```.
* ```tag.ancestor_ids``` is an array of the IDs of the ancestors.
* ```tag.ancestor_of?(node)``` returns true if current node is ancestor of another one
* ```tag.self_and_ancestors``` returns a scope containing self, parent, grandparent, great grandparent, etc.
* ```tag.self_and_ancestors_ids``` returns IDs containing self, parent, grandparent, great grandparent, etc.
* ```tag.siblings``` returns a scope containing all nodes with the same parent as ```tag```, excluding self.
* ```tag.sibling_ids``` returns an array of the IDs of the siblings.
* ```tag.self_and_siblings``` returns a scope containing all nodes with the same parent as ```tag```, including self.
* ```tag.descendants``` returns a scope of all children, childrens' children, etc., excluding self ordered by depth.
* ```tag.descendant_ids``` returns an array of the IDs of the descendants.
* ```tag.descendant_of?(node)``` returns true if current node is descendant of another one
* ```tag.self_and_descendants``` returns a scope of self, all children, childrens' children, etc., ordered by depth.
* ```tag.self_and_descendant_ids``` returns IDs of self, all children, childrens' children, etc., ordered by depth.
* ```tag.family_of?``` returns true if current node and another one have a same root.
* ```tag.hash_tree``` returns an [ordered, nested hash](#nested-hashes) that can be depth-limited.
* ```tag.find_by_path(path)``` returns the node whose name path *from ```tag```* is ```path```. See (#find_or_create_by_path).
* ```tag.find_or_create_by_path(path)``` returns the node whose name path *from ```tag```* is ```path```, and will create the node if it doesn't exist already.See (#find_or_create_by_path).
* ```tag.find_all_by_generation(generation_level)``` returns the descendant nodes who are ```generation_level``` away from ```tag```.
    * ```tag.find_all_by_generation(0).to_a``` == ```[tag]```
    * ```tag.find_all_by_generation(1)``` == ```tag.children```
    * ```tag.find_all_by_generation(2)``` will return the tag's grandchildren, and so on.
* ```tag.destroy``` will destroy a node and do <em>something</em> to its children, which is determined by the ```:dependent``` option passed to ```has_closure_tree```.

## Polymorphic hierarchies with STI

Polymorphic models using single table inheritance (STI) are supported:

1. Create a db migration that adds a String ```type``` column to your model
2. Subclass the model class. You only need to add ```has_closure_tree``` to your base class:

```ruby
class Tag < ActiveRecord::Base
  has_closure_tree
end
class WhenTag < Tag ; end
class WhereTag < Tag ; end
class WhatTag < Tag ; end
```

Note that if you call `rebuild!` on any of the subclasses, the complete Tag hierarchy will be emptied, thus taking the hiearchies of all other subclasses with it (issue #275). However, only the hierarchies for the class `rebuild!` was called on will be rebuilt, leaving the other subclasses without hierarchy entries.

You can work around that by overloading the `rebuild!` class method in all your STI subclasses and call the super classes `rebuild!` method:
```ruby
class WhatTag < Tag
  def self.rebuild!
    Tag.rebuild!
  end
end
```
This way, the complete hierarchy including all subclasses will be rebuilt.

If you need to preserve a certain children order to rebuild your tree you can call `rebuild` with the keyword `child_order` and give a regular ordering hash: `rebuild!(child_order: {name: :desc})`

## Deterministic ordering

By default, children will be ordered by your database engine, which may not be what you want.

If you want to order children alphabetically, and your model has a ```name``` column, you'd do this:

```ruby
class Tag < ActiveRecord::Base
  has_closure_tree order: 'name'
end
```

If you want a specific order, add a new integer column to your model in a migration:

```ruby
t.integer :sort_order
```

and in your model:

```ruby
class OrderedTag < ActiveRecord::Base
  has_closure_tree order: 'sort_order', numeric_order: true
end
```

When you enable ```order```, you'll also have the following new methods injected into your model:

* ```tag.siblings_before``` is a scope containing all nodes with the same parent as ```tag```,
  whose sort order column is less than ```self```. These will be ordered properly, so the ```last```
  element in scope will be the sibling immediately before ```self```
* ```tag.siblings_after``` is a scope containing all nodes with the same parent as ```tag```,
  whose sort order column is more than ```self```. These will be ordered properly, so the ```first```
  element in scope will be the sibling immediately "after" ```self```

If your ```order``` column is an integer attribute, you'll also have these:

* The class method ```#roots_and_descendants_preordered```, which returns all nodes in your tree,
  [pre-ordered](http://en.wikipedia.org/wiki/Tree_traversal#Pre-order).

* ```node1.self_and_descendants_preordered``` which will return descendants,
  [pre-ordered](http://en.wikipedia.org/wiki/Tree_traversal#Pre-order).

* ```node1.append_child(node2)``` (which is an alias to ```add_child```), which will
  1. set ```node2```'s parent to ```node1```
  2. set ```node2```'s sort order to place node2 last in the ```children``` array

* ```node1.prepend_child(node2)``` which will
  1. set ```node2```'s parent to ```node1```
  2. set ```node2```'s sort order to place node2 first in the ```children``` array
     Note that all of ```node1```'s children's sort_orders will be incremented

* ```node1.prepend_sibling(node2)``` which will
  1. set ```node2``` to the same parent as ```node1```,
  2. set ```node2```'s order column to 1 less than ```node1```'s value, and
  3. increment the order_column of all children of node1's parents whose order_column is > node2's new value by 1.

* ```node1.append_sibling(node2)``` which will
  1. set ```node2``` to the same parent as ```node1```,
  2. set ```node2```'s order column to 1 more than ```node1```'s value, and
  3. increment the order_column of all children of node1's parents whose order_column is > node2's new value by 1.

```ruby

root = OrderedTag.create(name: 'root')
a = root.append_child(Label.new(name: 'a'))
b = OrderedTag.create(name: 'b')
c = OrderedTag.create(name: 'c')

# We have to call 'root.reload.children' because root won't be in sync with the database otherwise:

a.append_sibling(b)
root.reload.children.pluck(:name)
=> ["a", "b"]

a.prepend_sibling(b)
root.reload.children.pluck(:name)
=> ["b", "a"]

a.append_sibling(c)
root.reload.children.pluck(:name)
=> ["b", "a", "c"]

b.append_sibling(c)
root.reload.children.pluck(:name)
=> ["b", "c", "a"]
```

### Ordering Roots

With numeric ordering, root nodes are, by default, assigned order values globally across the whole database
table. So for instance if you have 5 nodes with no parent, they will be ordered 0 through 4 by default.
If your model represents many separate trees and you have a lot of records, this can cause performance
problems, and doesn't really make much sense.

You can disable this default behavior by passing `dont_order_roots: true` as an option to your delcaration:

```
has_closure_tree order: 'sort_order', numeric_order: true, dont_order_roots: true
```

In this case, calling `prepend_sibling` and `append_sibling` on a root node or calling
`roots_and_descendants_preordered` on the model will raise a `RootOrderingDisabledError`.

The `dont_order_roots` option will be ignored unless `numeric_order` is set to true.


## Concurrency

Several methods, especially ```#rebuild``` and ```#find_or_create_by_path```, cannot run concurrently correctly.
```#find_or_create_by_path```, for example, may create duplicate nodes.

Database row-level locks work correctly with PostgreSQL, but MySQL's row-level locking is broken, and
erroneously reports deadlocks where there are none. To work around this, and have a consistent implementation
for both MySQL and PostgreSQL, [with_advisory_lock](https://github.com/ClosureTree/with_advisory_lock)
is used automatically to ensure correctness.

If you are already managing concurrency elsewhere in your application, and want to disable the use
of with_advisory_lock, pass ```with_advisory_lock: false``` in the options hash:

```ruby
class Tag
  has_closure_tree with_advisory_lock: false
end
```

Note that you *will eventually have data corruption* if you disable advisory locks, write to your
database with multiple threads, and don't provide an alternative mutex.

## I18n

You can customize error messages using [I18n](http://guides.rubyonrails.org/i18n.html):

```yaml
en-US:
  closure_tree:
    loop_error: Your descendant cannot be your parent!
```

## FAQ

### Are there any how-to articles on how to use this gem?

Yup! [Ilya Bodrov](https://github.com/bodrovis) wrote [Nested Comments with Rails](http://www.sitepoint.com/nested-comments-rails/).

### Does this work well with ```#default_scope```?

**No.** Please see [issue 86](https://github.com/ClosureTree/closure_tree/issues/86) for details.

### Can I update parentage with `update_attribute`?

**No.** `update_attribute` skips the validation hook that is required for maintaining the
hierarchy table.

### Can I assign a parent to multiple children with  ```#update_all```?

**No.** Please see [issue 197](https://github.com/ClosureTree/closure_tree/issues/197) for details.

### Does this gem support multiple parents?

No. This gem's API is based on the assumption that each node has either 0 or 1 parent.

The underlying closure tree structure will support multiple parents, but there would be many
breaking-API changes to support it. I'm open to suggestions and pull requests.

### How do I use this with test fixtures?

Test fixtures aren't going to be running your ```after_save``` hooks after inserting all your
fixture data, so you need to call ```.rebuild!``` before your test runs. There's an example in
the spec ```tag_spec.rb```:

```ruby
  describe "Tag with fixtures" do
    fixtures :tags
    before :each do
      Tag.rebuild! # <- required if you use fixtures
    end
```

**However, if you're just starting with Rails, may I humbly suggest you adopt a factory library**,
rather than using fixtures? [Lots of people have written about this already](https://www.google.com/search?q=fixtures+versus+factories).

### There are many ```lock-*``` files in my project directory after test runs

This is expected if you aren't using MySQL or Postgresql for your tests.

SQLite doesn't have advisory locks, so we resort to file locking, which will only work
if the ```FLOCK_DIR``` is set consistently for all ruby processes.

In your ```spec_helper.rb``` or ```minitest_helper.rb```, add a ```before``` and ```after``` block:

```ruby
before do
  ENV['FLOCK_DIR'] = Dir.mktmpdir
end

after do
  FileUtils.remove_entry_secure ENV['FLOCK_DIR']
end
```

### `bundle install` says `Gem::Ext::BuildError: ERROR: Failed to build gem native extension`

When building from source, the `mysql2`, `pg`, and `sqlite` gems need their native client libraries
installed on your system. Note that this error isn't specific to ClosureTree.

On Ubuntu/Debian systems, run:

```
sudo apt-get install libpq-dev libsqlite3-dev libmysqlclient-dev
bundle install
```

### Object destroy fails with MySQL v5.7+

A bug was introduced in MySQL's query optimizer. [See the workaround here](https://github.com/ClosureTree/closure_tree/issues/206).

### Hierarchy maintenance errors from MySQL v5.7.9-v5.7.10

Upgrade to MySQL 5.7.12 or later if you see [this issue](https://github.com/ClosureTree/closure_tree/issues/190):

    Mysql2::Error: You can't specify target table '*_hierarchies' for update in FROM clause

## Testing with Closure Tree

Closure tree comes with some RSpec2/3 matchers which you may use for your tests:

```ruby
require 'spec_helper'
require 'closure_tree/test/matcher'

describe Category do
 # Should syntax
 it { should be_a_closure_tree }
 # Expect syntax
 it { is_expected.to be_a_closure_tree }
end

describe Label do
 # Should syntax
 it { should be_a_closure_tree.ordered }
 # Expect syntax
 it { is_expected.to be_a_closure_tree.ordered }
end

describe TodoList::Item do
 # Should syntax
 it { should be_a_closure_tree.ordered(:priority_order) }
 # Expect syntax
 it { is_expected.to be_a_closure_tree.ordered(:priority_order) }
end

```

## Testing

Closure tree is [tested under every valid combination](http://travis-ci.org/#!/ClosureTree/closure_tree) of

* Ruby 2.5, 2.6 and 2.7
* ActiveRecord 4.2, 5.x and 6.0
* PostgreSQL, MySQL, and SQLite. Concurrency tests are only run with MySQL and PostgreSQL.

Assuming you're using [rbenv](https://github.com/sstephenson/rbenv), you can use ```tests.sh``` to
run the test matrix locally.

## Change log

See the [change log](https://github.com/ClosureTree/closure_tree/blob/master/CHANGELOG.md).

## Thanks to

* The 45+ engineers around the world that have contributed their time and code to this gem
  (see the [changelog](https://github.com/ClosureTree/closure_tree/blob/master/CHANGELOG.md)!)
* https://github.com/collectiveidea/awesome_nested_set
* https://github.com/patshaughnessy/class_factory
* JetBrains, which provides an [open-source license](http://www.jetbrains.com/ruby/buy/buy.jsp#openSource) to
  [RubyMine](http://www.jetbrains.com/ruby/features/) for the development of this project.
