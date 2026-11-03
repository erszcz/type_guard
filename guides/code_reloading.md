# Code reloading

TypeGuard keeps no cache, so code reloading needs no extra setup.

## Why no cache is needed

The check of a type is a function in the module that defines the type. A
check that uses a type of another project module calls that function at
runtime. When the code reloader, `recompile/0` in IEx or a hot upgrade
replaces a module, it replaces the module's checks with it, and every check
that uses its types calls the new ones.

This also covers a change to a type alone. Such a change does not change the
code of the module or its `module_info(:md5)`, but it does change the code of
the generated checks.

The alternative would be to read typespecs at runtime. They are in the debug
chunk of the compiled file, not in loaded code, so each read decodes the
file, and a cache of the results would need its own invalidation on reload.

## Types of other applications

The checks of types of other applications are inlined at compile time.
These modules do not change while the project runs. When they change, for
example after a dependency upgrade, the modules that inline their types
recompile, because the generated code `require`s them.

## In-memory modules

A module defined with `Code.compile_string/2` or IEx `r/1` is replaced in
memory only. Its checks are replaced with it, so reloading works the same.
