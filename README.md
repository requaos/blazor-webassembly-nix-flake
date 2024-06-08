# Blazor WebAssembly in .NET

This flake defines:

* `nix develop . --command alejandra .` to run the [Alejandra](https://github.com/kamadorueda/alejandra) Nix source formatter.
* `nix develop . --command markdown-link-check README.md` to check that this README's links are not broken.
* `nix develop . --command bash -c "find . -type f -name '*.sh' | xargs shellcheck"` to check all shell scripts in this repository.
* `nix run .#fetchDeps` to collect the [NuGet] dependencies of the project into the [lockfile](./nix/deps.nix). (You only have to run this after you change the NuGet dependencies of the .NET projects.)
* `nix build .` to publish webapp files to the nix store and symlink to a `result` directory at the root of this repository.

## Development

When you want to add a [NuGet] dependency, you will have to rerun `nix run .#fetchDeps`, whose output will be written to `./nix/deps.nix`.
If you forget to do this, you'll see `nix build` fail at the NuGet restore stage, because it's not talking to NuGet but instead is using the dependencies present in the Nix store; if you haven't run `fetchDeps`, those dependencies will not be in the store.
(Note that the file as generated does not conform to Alejandra's formatting requirements, so you will probably also want to `nix develop . --command alejandra .` afterwards.)

[NuGet](https://www.nuget.org)
