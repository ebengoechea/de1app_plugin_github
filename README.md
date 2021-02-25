# GitHub plugins DE1app plugin

A DE1app plugin to install and update plugins from GitHub on your [Decent Espresso machine app](https://github.com/decentespresso/de1app).

This is a spin-off of the [Describe Your Espresso](https://github.com/ebengoechea/dye_de1app_dsx_plugin) DSx plugin auto-updater code.

This plugin (hopefully) will be bundled with the DE1app. Enable it on the extensions page (Settings > App > Extensions > GitHub plugins). To install manually, copy the repository contents to your tablet folder **de1plus/plugins/github**. Then visit the plugin settings page.

DE1app plugins whose source code is hosted in GitHub can be bundled with the DE1app and they are installed and updated automatically together with the DE1 tablet app. This is in fact the preferred distribution mechanism. Then, why this plugin?

1. Some authors may prefer not to include their plugins in the DE1 app distribution, because their plugins are somehow optional (for example, a [demo for other plugin](https://github.com/ebengoechea/de1app_plugin_DGUI_Demo), only needed to showcase features to other developers) or for any other reason. This plugin offers an alternative distribution mechanism that frees users of cumbersome manual installation and updates.
2. Even for plugins included in the DE1 app distribution, an author may want to release an update (say, with a bug patch) that some users need urgently and cannot wait till the next official version.
3. Even for plugins included in the DE1 app distribution, some users may prefer to be on the stable branch of the app, but still want to use the last version of some plugin.

Please note that in cases 2 and 3, when the next DE1 app update is installed, it will overwrite whatever the user has updated manually from GitHub, but this shouldn't be a problem if the plugin author has coordinated the versions correctly. 

*WARNING for users:* **Plugins bundled with the DE1app have normally been tested to work before release by the DE1app integrator. If you install or update from GitHub, you're at the expense of the testing done only the plugin author. So, use at your own risk**.

### For plugin authors: How do I make my plugin use GitHub updates?

1. Your plugin should reside on its own GitHub repository, and should only contain the files that will be copied to the `de1plus/plugins/<your_plugin_name>` folder.
2. Include the namespace variable `github_url` on your plugin namespace, pointing to your github repository.
3. If your plugin is ##not## bundled with the DE1 app and you want it listed, tell @ebengoechea to include it, providing the GitHub repo URL, or ask users to add it manually on the plugin settings page.
4. Whenever you want to release a new version, you have to tag the commit with the version number (with or without a leading "v", e.g. it can be `1.02` or `v1.02`), and create a release from it on GitHub's web interface.

Users will then be able to install and/or update your plugin from the "GitHub plugins" plugin page. If you want to include an auto-updater button on your own plugin pages, you can use the following example code:
```tcl
TO BE ADDED SOON
```
