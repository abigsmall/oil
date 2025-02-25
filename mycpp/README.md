mycpp
=====
 
This is an experimental Python-to-C++ translator based on MyPy.  It only
handles the small subset of Python that Oil uses.

It's inspired by both mypyc and Shed Skin.  These posts give background:

- [Brief Descriptions of a Python to C++ Translator](https://www.oilshell.org/blog/2022/05/mycpp.html)
- [Oil Is Being Implemented "Middle Out"](https://www.oilshell.org/blog/2022/03/middle-out.html)

## Instructions

### Translating and Compiling `oil-native`

Running `mycpp` is best done on a Debian / Ubuntu-ish machine.  Follow the
instructions at <https://github.com/oilshell/oil/wiki/Contributing> to create
the "dev build" first, which is DISTINCT from `oil-native`.  Make sure you can
run:

    oil$ build/dev.sh all

This will give you a working shell:

    oil$ bin/osh -c 'echo hi'  # running interpreted Python
    hi

To run mycpp, you'll need the MyPy source repository, as well as a virtualenv
containing MyPy's dependencies.  The instructions at the top of `deps.sh` give
details:

    oil$ mycpp/deps.sh git-clone
    oil$ mycpp/deps.sh pip-install

To build oil-native, use:

    oil$ build/dev.sh oil-cpp  # translate and compile, may take 30 seconds

    oil$ _bin/osh_eval.dbg -c 'echo hi'  # running compiled C++ !
    hi

To run the tests and benchmarks, follow the instructions at the top of `deps.sh`.

If you have problems, post a message on `#oil-dev` at
`https://oilshell.zulipchat.com`.  Not many people have contributed to `mycpp`,
so I can use your feedback!


### Run Tests and Benchmarks

    ./build_graph.py
    ninja logs-equal       # test for correctness by comparing stdout
    ninja benchmark-table  # make a table of time/memory usage

To build and run one example, like `fib_iter`:

    ninja _ninja/tasks/test/fib_iter.py.task.txt

To list targets:

    ninja -t targets

### Clean

Unfortunately, you may need to clean the build, since some dependencies
aren't accounted for:

    ./build.sh clean

## Notes on the Algorithm / Architecture

There are four passes over the MyPy AST.

(1) `const_pass.py`: Collect string constants 

Turn turn the constant in `myfunc("foo")` into top-level `GLOBAL_STR(str1,
"foo")`.
  
(2) Three passes in `cppgen_pass.py`.

(a) Forward Declaration Pass.

    class Foo;
    class Bar;

This pass also determines which methods should be declared `virtual` in their
declarations.  The `virtual` keyword is written in the next pass.

(b) Declaration Pass.

    class Foo {
      void method();
    };
    class Bar {
      void method();
    };

More work in this pass:

- Collect member variables and write them at the end of the definition
- Collect locals for "hoisting".  Written in the next pass.
- Creates `fmtN()` functions to compile Python's `%` formatting operator.

(c) Definition Pass.

    void Foo:method() {
      ...
    }
    void Bar:method() {
      ...
    }

Note: I really wish we were not using visitors, but that's inherited from MyPy.

## Translation Notes

### Major Features

- Instantiating objects &rarr; `gc_heap::Alloc<T>(...)`
- Collections
  - `str` &rarr; `Str*`
  - `List[T]` &rarr; `List<T>*`
  - `Dict[K, V]` &rarr; `Dict<K, V>*`
  - Semantic change: a `Tuple[str, int]` is a **value type** that can only be
    returned from a function.  If you want a garbage-collected **reference
    type**, use an ASDL record `(string s, int i)`
- Collection literals turn into initializer lists
  - And there is a C++ type inference issue which requires an explicit
    `std::initializer_list<int>{1, 2, 3}`, not just `{1, 2, 3}`
- Python's polymorphic iteration &rarr; `StrIter`, `ListIter<T>`, `DictIter<K,
  V`
  - `d.iteritems()` is rewritten `mylib.iteritems()` &rarr; `DictIter`
    - TODO: can we be smarter about this?
  - `reversed(mylist)` &rarr; `ReverseListIter`
- Python's `in` operator:
  - `s in mystr` &rarr; `str_contains(mystr, s)`
  - `x in mylist` &rarr; `list_contains(mylist, x)`
- Classes and inheritance
  - `__init__` method becomes a constructor.  Note: initializer lists aren't
    used.
  - Detect `virtual` methods
  - TODO: could we detect `abstract` methods? (`NotImplementedError`)
- Python Exceptions &rarr; C++ exceptions
- Scope-based resource management
  - `with ctx_Foo(...)` &rarr; C++ constructors and destructors
- Python Modules &rarr; C++ namespace (we assume a 2-level hierarchy)
- A "clever" hack: `with tagswitch(d) as case` &rarr; `switch / case`
  - We don't have Python 3 pattern matching

### Minor Translations

- `s1 == s2` &rarr; `str_equals(s1, s2)`
- `[None] * 3` &rarr; `list_repeat(nullptr, 3)`
- Omitted:
  - If the LHS of an assignment is `_`, then the statement is omitted
    - This is for `_ = log`, which shuts up Python lint warnings for 'unused
      import'
  - Code under `if __name__ == '__main__'`

## C++ Features Used

- For ASDL: type-safe enums, i.e. `enum class`
- `nullptr`
- `static_cast` and `reinterpret_cast`
- Some Function Overloading for `format_r`?
  - Do we need this for equality and hashing?
- `offsetof` for introspection of field positions for garbage collection
- `std::initializer_list` for `StackRoots()`
  - Should we get rid of this?

### Not Used

- I/O Streams, RTTI, etc.
- `const`
- No smart pointers for now

## Notes on the Runtime (`mylib`)

- A `Str` is immutable, and can be used as a key to a `Dict` (at the Python
  level), and thus an `AssocArray` (at the Oil level).
- A `BufWriter` is mutable.  It's an alias for `cStringIO.StringIO()`.  You
  build it with repeated calls to`write()`, and then call `getvalue()` at the
  end.

## `mycpp` Limitations

### Due to the Translation or C++ language

- C++ doesn't have `try / except / else`, or `finally`
  - This usually requires some rewriting
- `if mylist` tests if the pointer is non-NULL; use `if len(mylist)` for
  non-empty test
- Functions can have at most one keyword / optional argument.
  - We generate two methods: `f(x)` which calls `f(x, y)` with the default
    value of `y`
  - If there are two or more optional arguments:
    - For classes, you can use the "builder pattern", i.e. add an
      `Init_MyMember()` method
    - If the arguments are booleans, translate it to a single bitfield argument
- C++ has nested scope and Python has flat function scope.  Can cause name
  collisions.
  - Could enforce this if it becomes a problem

### Due to Garbage Collection

- Big limitation: I think `f(g(x))` is not allowed if g() returns a
  pointer!  Due to `StackRoots`.
  - TODO: enforce this or translate it.
- Likewise `for x in [1, 2, 3]` is not allowed.  Assign it to a temporary
  variable first, so it can be picked up in `StackRoots()`.
- Generally constructors should only assign members.  They shouldn't call
  functions or raise exceptions.
  - TODO: we could enforce this.

## Gotchas

- C++ classes can have 2 member variables of the same name!  From the base
  class and derived class.
- Failing to declare methods `virtual` can involve the wrong one being called
  at runtime
