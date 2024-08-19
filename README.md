# CDFModule

Powershell module for Epical Cloud Deployment Framework

## Releases of CDFModule

Versioning of CDFModule follows semantic versioning with `<major>.<minor>.<patch>`. This is the versioning scheme supported by PowerShell module manifest. The version is managed by using Git Tags.

Releases are either "live" release or "pre-release". Pre-releases are used when preparing a new minor release of the CDFModule. Multiple pre-release patch versions can be made to reach the new "live" minor version.

For a "live" release version the patch version is used according to the name; that is for **patching** and must not include any breaking changes but may add new features if they can be incorporated without breaking existing functionality.

The git tags uses a `v` prefix and `-pre` suffix for pre-releases following a naming pattern of `v<major>.<minor>.<patch>[-pre]`.
So the difference between making a release and a pre-release is in the tag name where a pre-release would have the suffix `-pre`.

The workflow [release-cdfmodule](.github/workflows/release-cdfmodule.yaml) will trigger on tags matching the regexp `v[0-9]+.[0-9]+.[0-9]+` and package the module in a versioned release.

The workflow [prerelease-cdfmodule](.github/workflows/prerelease-cdfmodule.yaml) will trigger on tags matching the regexp `v[0-9]+.[0-9]+.[0-9]+-pre` and package the module in a versioned release.

A new pre-release or release is all about git tag on the commit to serve as the release version. Any "live" releases should preferably be made from `main` branch but it is not required as such. For pre-release the branch will likely be `development` or `feature-<name>`

Make sure you are on the correct branch and commit when tagging from command line and via web ui for that matter. Tags and releases can be deleted and remade. So no worries.

### Create release and pre-release

Making new releases and pre-release through tagging:

```shell
# Before assigning new tags it is a good idea to sync local tags with remote
# This will remove all local tags so make sure you push any local tags you want to keep
git tag -l | xargs git tag -d  # Unix
git tag -l | %{git tag -d $_}  # PowerShell
git fetch --tags

# Make a first pre-release for upcoming version "1.2"
git tag -a v1.2.0-pre
git push --tags

# ...make some pre-release code changes and pre-release...

git tag -a v1.2.1-pre
git push --tags

# ...make additional pre-release code changes and pre-release...

git tag -a v1.2.2-pre
git push --tags

# Ready for the first release of version "1.2"
git tag -a v1.2.0
git push --tags

# Afterwards, after a while, you should remove all remaining obsolete pre-releaseses v1.2.xx-pre

# ...make a patch code changes...

# Release the patch version of "1.2.1"
git tag -a v1.2.1
git push --tags

```

### Remove release and pre-release

When workflows work as they should there will always be a release for a tag. Hence the normal procedure will be to remove a release and its associated tag. Cleaning up pre-release after a release is such case.

Sometimes the tag might have the wrong name and then you want to remove it from remote.

```shell
# Removing a tag remote
git push --delete origin v1.1.1-pre

# Removing a release and the tag with it
gh release delete v1.0.1-pre --cleanup-tag -y

# When removing a tag remote you must refresh local tags by removing and fetching
git tag -l | xargs git tag -d
git fetch --tags

```
# cdf-templates
