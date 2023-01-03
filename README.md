# Source Control Management Plugin

This plugin provides base functionality that allows you to easily add support
for any source control management system while saving you from having to
re-implement editor integration. It uses Lite XL `process` api to allow
async calling of the SCM binaries.

You can easily implement your own SCM backend by extending `plugins.scm.backend`,
the plugin will take care of the rest for you. Currently it ships with the
following backends:

* [Git](backend/git.lua)
* [Fossil](backend/fossil.lua)

Any of the backends listed above can serve you as an example or template to
implement your own.

## Usage and Requirements

You will need to have the SCM binaries installed and accesible from
your `PATH` environment variable:

* [git](https://git-scm.com/) - for projects versioned in git
* [fossil](https://www.fossil-scm.org/) - for projects versioned in fossil
* [language_diff](https://github.com/lite-xl/lite-xl-plugins/blob/master/plugins/language_diff.lua) plugin, optional but recommended
* [Widgets](https://github.com/lite-xl/lite-xl-widgets) for confirmation messages, etc...

Follow the usual plugin installation procedure. When opening projects the
backend will be auto detected by using the backend's `detect()` method. Then
it will be associated to the project for subsequente use.

## Features

* Support for multiple projects (not tested).
* Show current branch and stats on status bar.
* View the current project diff on a new doc view by executing the
  `scm:global-diff` command or clicking on the status bar SCM item.
* Colorize the treeview files depending on the item status which can be:
  - added
  - renamed
  - deleted,
  - edited
  - untracked
* Draw file changes on the doc view which includes:
  - additions
  - deletions
  - modifications

## TODO

There is still missing functionality, but some of the following comes to mind:

- [ ] Pull and push
- [ ] detecting if the SCM binaries are missing
- [ ] maybe... allow configuring the SCM binaries path
- [ ] colorize tabs text depending on the file status
- [x] restoring a file to a previous state
- [ ] view the commit history of project or file
- [x] view diff of a specific file: `scm:file-diff`
- [x] add, rename and remove files in version control
- [ ] be able to commit current changes

Suggestions for how to implement the above features are welcome as other ideas
not listed above.

## Credits

Thanks to the authors of [gitdiff](https://github.com/vincens2005/lite-xl-gitdiff-highlight)
and [gitstatus](https://github.com/lite-xl/lite-xl-plugins/blob/master/plugins/gitstatus.lua)
which code served as a source of copy-pasting and inspiration!
