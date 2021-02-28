#######################################################################################################################
### A Decent DE1 app plugin to install and update other plugins from their GitHub repositories.
#######################################################################################################################
package require de1_logging 1.0

namespace eval ::plugins::github {
	variable author "Enrique Bengoechea"
	variable contact "enri.bengoechea@gmail.com"
	variable version 1.00
	variable github_repo ebengoechea/de1app_plugin_github
	variable name [translate "GitHub plugins"]
	variable description [translate "Install and update DE1 app plugins from their GitHub repositories.
BEWARE these are not tested nor validated by Decent, only by plugin authors. Use at your own risk."]

	namespace export latest_release plugin_repo update_plugin download_repo_file
}

proc ::plugins::github::main {} {	
	variable settings
	package require http
	package require tls
	package require json
	package require zipfs
	
	if { [plugins available DGUI] } {
		plugins load DGUI
	} else {
		error [translate "Can't load github plugin because required plugin DGUI is not available"]
	}

	msg "Starting the 'GitHub plugins' plugin"
	if { ![info exists ::debugging] } { set ::debugging 0 }	
	
	check_settings
	save_plugin_settings github
}

# Paint settings screen
proc ::plugins::github::preload {} {
	variable data
	
	if { [plugins available DGUI] } {
		plugins preload DGUI
		::plugins::DGUI::set_symbols cloud_download_alt "\uf381" trash_undo "\uf895" sync "\uf021"
		::plugins::github::CFG::setup_ui
		return "::plugins::github::CFG"
	} else {
		return ""
	}
}

proc ::plugins::github::check_settings {} {
	variable settings

	ifexists settings(latest_release_url) "https://api.github.com/repos/<REPO>/releases/latest"
	ifexists settings(repo_file_url) "https://api.github.com/repos/<REPO>/contents/<PATH>"
	
	foreach s {plugins_last_update plugins names repos published_at installed_versions github_versions
			github_versions_flags zipball_urls html_urls release_descs status nondist_plugins } {
		if { ![info exists settings($s)] } {
			set settings($s) {}
		}
	}
}

proc ::plugins::github::msg { {flag ""} args } {
	if { [string range $flag 0 0] eq "-" && [llength $args] > 0 } {
		::logging::default_logger $flag "::plugins::github" {*}$args
	} else {
		::logging::default_logger "::plugins::github" $flag {*}$args
	}
}

proc ::plugins::github::plugin_dir { plugin } {
	return "[homedir]/[plugin_directory]/$plugin"
}

proc ::plugins::github::plugin_backup_dir { plugin } {
	return "[homedir]/tmp/${plugin}_backup"
}

proc ::plugins::github::plugin_repo { plugin } {
	variable settings
	set repo ""
	
	if { $plugin eq "" } {
		msg -WARN "emtpy plugin in plugin_repo"
		return
	} 
	
	if { [info exists ::plugins::${plugin}::github_repo] } {
		set repo [subst \$::plugins::${p}::github_repo]
	} else {
		array set nondist_plugins $settings(nondist_plugins)
		
		if { [array names nondist_plugins -exact $p] eq "$p" } {
			set repo $nondist_plugins($p)
		}
	}
	
	if { $repo eq "" } {
		msg -WARN "plugin '$plugin' has to GitHub repository available"
	}
	return $repo	
}

proc ::plugins::github::latest_release_url { repo } {
	variable settings
	regsub "<REPO>" $settings(latest_release_url) $repo link
	return $link
}

# Queries GitHub repository for the latest released version and returns a list than can be casted to an array 
# 	with names 'version', 'published_at', 'draft', 'prerelease', 'name', 'zipball_url', 'html_url', and 'body'.
# If there's an error or the data can't be downloaded, returns all array values empty except version=-1, 
#	name=ERROR, and body=<error_description>.
proc ::plugins::github::latest_release { repo } {
	array set result {
		version -1
		published_at {}
		draft {}
		prerelease {}
		name ERROR
		zipball_url {}
		html_url {}
		body {}
	}
	
	set url [latest_release_url $repo]
	if { $repo eq "" || $url eq "" } {
		msg -WARN "empty repo or url in latest_release"
		set result(body) [translate "No GitHub URL"]
		return [array get result]
	}
	
	::http::register https 443 ::tls::socket
	
	msg "querying latest release url $url"
	set status ""
	set answer ""
	set code ""
	set ncode ""
	if {[catch {
		set token [::http::geturl $url -timeout 10000]
		set status [::http::status $token]
		set answer [::http::data $token]
		set ncode [::http::ncode $token]
		set code [::http::code $token]
		::http::cleanup $token
	} err] != 0} {
		set my_err "Could not get latest release from GitHub"
		msg -WARN "$my_err : $err"
		say [translate "Download failed"] ""
		catch { ::http::cleanup $token }
		set result(body) [translate $my_err]
	}
	
	if { $status eq "ok" && $ncode == 200 } {
		if {[catch {
			set response [::json::json2dict $answer]
			set tag_name [dict get $response tag_name]
			set result(published_at) [dict get $response published_at]
			set result(draft) [dict get $response draft]
			set result(prerelease) [dict get $response prerelease]
			set result(name) [dict get $response name]
			set result(zipball_url) [dict get $response zipball_url]
			set result(html_url) [dict get $response html_url]
			set result(body) [dict get $response body]
			
			regsub {^v* *([0-9\.\-]+) *$} $tag_name "\\1" result(version)
		} err] != 0} {
			set my_err "Unexpected GitHub server answer"
			msg -WARN "$my_err : $answer"
			say [translate "Download failed"] ""
			set result(body) [translate $my_err]
		}		
	} else {
		set my_err "Could not get latest release from GitHub"
		msg -WARN "$my_err : $code $answer"
		say [translate "Download failed"] ""
		set result(body) [translate $my_err]
	}
	
	return [array get result]
}

proc ::plugins::github::repo_file_url { repo path } {
	variable settings
	regsub "<REPO>" $settings(repo_file_url) $repo link
	regsub "<PATH>" $link $path link
	return $link
}

proc ::plugins::github::download_repo_file { repo path target_path } {
	if { $repo eq "" || $path eq "" } {
		msg -WARN "empty repo or path in download_repo_file"
		return
	}
	
	set url [repo_file_url $repo $path]
	if { $target_path eq "" } {
		set target_path "[homedir]/tmp/$path"
	}
		
	::http::register https 443 ::tls::socket
	
	msg "querying download url $url"
	set status ""
	set ncode ""
	if {[catch {
		set token [::http::geturl $url -timeout 10000]
		set status [::http::status $token]
		set answer [::http::data $token]
		set ncode [::http::ncode $token]
		set code [::http::code $token]
		::http::cleanup $token
	} err] != 0} {
		set my_err "Could not get content url $url"
		msg -WARN "$my_err : $err"
		say [translate "Download failed"] ""
		catch { ::http::cleanup $token }
		return
	}
	
	if { $status eq "ok" && $ncode == 200 } {
		if {[catch {
			set response [::json::json2dict $answer]
			set download_url [dict get $response download_url]
		} err] != 0} {
			set my_err "Unexpected GitHub server answer"
			msg -WARN "$my_err : $answer"
			say [translate "Download failed"] ""
			return
		}		
	} else {
		set my_err "Could not get content url $url"
		msg -WARN "$my_err : $code"
		say [translate "Download failed"] ""
		return
	}
	
	::decent_http_get_to_file $download_url $target_path
}

proc ::plugins::github::download_nondist_plugin_list {} {
	variable github_repo
	download_repo_file $github_repo plugins.tdb "[plugin_dir github]/plugins.tdb"
}

# Reads the plugins.tdb file, which contains the list of plugins to be included in any case, even if they
# 	are not included in the DE1app distribution, and moves any entry not already included to settings(nondis_plugins).
proc ::plugins::github::load_nondist_plugin_list {} {
	variable settings 
	
	set needs_save_settings 0
	array set settings_nondist_plugins $settings(nondist_plugins)
	
	set fn "[homedir]/[plugin_directory]/github/plugins.tdb"
	if { [file exists $fn] } {
		set plugin_contents [encoding convertfrom utf-8 [read_binary_file $fn]]
		if {[string length $plugin_contents] != 0} {
			array set nondist_plugins $plugin_contents

			foreach p [array names nondist_plugins] {
				if { [lsearch -exact [array names settings_nondist_plugins] $p] == -1 } {
					set settings_nondist_plugins($p) $nondist_plugins($p)
					set needs_save_settings 1
				}
			}
			
			if { $needs_save_settings } {
				set settings(nondist_plugins) [array get settings_nondist_plugins]
				plugins save_settings github
			}
		}
	} else {
		msg -WARN "file 'plugins.tdb' not found"
	}
}

# Determines the list of available plugins and queries GitHub for the latest release of each one, storing the
#	results in each of the corresponding settings array items. 
# The list of plugins is built adding installed ones that have a 'github_repo' namespace variable, to "fixed"
#	ones set up in file plugins.tdb.
# Returns 0 if the list cannot be updated, 1 otherwise.
proc ::plugins::github::update_list {} {
	variable settings
	
	set settings(plugins_last_update) [clock milliseconds]
	foreach s {plugins names repos published_at installed_versions github_versions github_versions_flags 
			zipball_urls html_urls release_descs status } {
		set settings($s) {}
	}
	
	# Start with the list of all available plugins, and add those that are defined in the settings.
	set all_plugins [plugins list]
	array set nondist_plugins $settings(nondist_plugins)
	lappend all_plugins {*}[array names nondist_plugins]	
	set all_plugins [lsort -dictionary -nocase -unique $all_plugins]
	
	foreach p $all_plugins {
		if { [info exists ::plugins::${p}::github_repo] } {
			lappend settings(plugins) $p
			set repo [subst \$::plugins::${p}::github_repo]
			lappend settings(repos) $repo
		} elseif { [array names nondist_plugins -exact $p] eq "$p" } {
			lappend settings(plugins) $p
			set repo $nondist_plugins($p)
			lappend settings(repos) $repo
		} else { 
			continue
		}
			
		if { [info exists ::plugins::${p}::name] } {
			lappend settings(names) [subst \$::plugins::${p}::name]
		} else {
			lappend settings(names) $p
		}			
		
		if { [info exists ::plugins::${p}::version] } {
			set installed_version [subst \$::plugins::${p}::version]
		} else {
			set installed_version ""
		}
		lappend settings(installed_versions) $installed_version
		
		array set release [::plugins::github::latest_release $repo]
		set github_version $release(version)
		lappend settings(github_versions) $github_version
		set version_flag ""
		if { [string is true $release(draft)] } {
			append version_flag " DRAFT"
		}
		if { [string is true $release(prerelease)] } {
			append version_flag " PRERELEASE"
		}			
		lappend settings(github_versions_flags) [string trim $version_flag]
		
		if { $release(published_at) ne "" } {
			if { [catch { 
				lappend settings(published_at) [clock scan $release(published_at) -format "%Y-%m-%dT%H:%M:%SZ"]
			} err ] != 0 } {
				lappend settings(published_at) $release(published_at)
				msg -WARN "can't parse github published_at date string '$release(published_at)'"
			}
		}
		lappend settings(zipball_urls) $release(zipball_url)
		lappend settings(html_urls) $release(html_url)
		lappend settings(release_descs) $release(body)
		
		if { $github_version == -1 || $github_version eq "" } {
			lappend settings(status) "not_found"
		} elseif { $installed_version eq "" } {
			lappend settings(status) "install_available"
		} else {
			if { [package vcompare $github_version $installed_version ] > 0 } {
				lappend settings(status) "update_available"
			} else {
				lappend settings(status) "uptodate"
			}
		}
	}
	
	plugins save_settings github
}

proc ::plugins::github::update_plugin { plugin {repo {}} {zipball_url {}} {make_backup 1} } {
	if { $zipball_url eq "" } {
		if { $repo eq "" } {
			set repo [plugin_repo $plugin]
		}
		
		if { $repo ne "" } {
			array set release [latest_release $repo]
			set zipball_url $release(zipball_url)
		}
	}
	if { $zipball_url eq "" } {
		msg -WARN "update_plugin: no zipball_url found for plugin '$plugin'"
		return 0
	}
	
	::http::register https 443 ::tls::socket
	
	if {[catch {
		set token [::http::geturl $zipball_url -timeout 30000]
		set status [::http::status $token]
		set meta [::http::meta $token]
		set ncode [::http::ncode $token]
		set code [::http::code $token]
		::http::cleanup $token
	} err] != 0} {
		msg -WARN "Could not get latest release ZIP answer from GitHub! $err"
		say [translate "Download failed"] ""
		catch { ::http::cleanup $token }
		return 0
	}
	
	set zip_url {}
	if { $status eq "ok" && $ncode == 302} {
		if {[catch {
			set zip_url [dict get $meta Location]
		} err] != 0} {
			msg -WARN "Unexpected meta format from GitHub! $err"
			say [translate "Download failed"] ""
			return 0
		}			
	} else {
		msg -ERROR "Could not get latest release from GitHub! $code"
		say [translate "Download failed"] ""
		return 0	
	}
	
	set zip_fn "${plugin}_latest.zip"
	set zip_path "[homedir]/tmp/$zip_fn"
	if { [file exists $zip_path] } {
		file delete $zip_path
	}
	
	::decent_http_get_to_file $zip_url $zip_path
	
	if { [file exists $zip_path] } {
		if {[catch {
			cd [file dirname $zip_path]
			set mnt_point [zipfs::mount $zip_path __zip]
		} err] != 0} {
			msg -WARN "Could not get uncompress ZIP or unexpected ZIP contents: $err"
			say [translate "Download failed"] ""
			catch { zipfs::unmount $zip_path }
			catch { file delete $zip_path } 
			return 0
		}
		
		cd __zip
		# Main folder is the concatenation of the repo (with / replaced by -) with the commit short hash. Just cd into it.
		set dir_name [glob *]
		
		if { [llength $dir_name] == 1 && [file isdirectory $dir_name] } {
			cd $dir_name
			
			set target_path "[plugin_dir $plugin]"
			file mkdir $target_path
			
			foreach fn [glob -nocomplain *] {
				unzip_one "$fn" "$target_path"
				
#				if { [zipfs exists $plugin_file] } {
#					set current_plugin_path "[skin_directory]/DSx_Plugins/${plugin_file}"
#					if { $save_backup == 1 && [file exists $current_plugin_path] } {
#						set backup_path "[skin_directory]/DSx_Plugins/[file rootname $plugin_file]_previous.off"
#						file copy -force $current_plugin_path $backup_path
#					}
#					file copy -force $plugin_file "[skin_directory]/DSx_Plugins/${plugin_file}" 
#				} else {
#					msg -WARN "Could not find plugin file inside ZIP: $err"
#					say [translate "Download failed"] ""
#					catch { zipfs unmount $zip_path }
#					catch { file delete $zip_path }
#					return 0
#				}
			}
		} else {
			msg "DYE: Donwloaded ZIP does not have the expected structure: $err"
			say [translate "Download failed"] ""
			catch { zipfs unmount $zip_path }
			catch { file delete $zip_path }
			return 0
		}

		catch { zipfs unmount $zip_path }
		catch { file delete $zip_path }
		return 1
	} else {
		msg "Could not download ZIP file"
		say [translate "Download failed"] ""
		return 0
	}
}

proc ::plugins::github::unzip_one { file_name destination } {
	if { [file isdirectory $file_name] } {
		mkdir "$destination/$file_name"
		foreach fn [glob -nocomplain "$file_name/*"] {
			unzip_one $fn "$destination/$file_name"
		}
	} else {
		file copy -force $file_name "$destination/$file_name"
	}
}

### PLUGIN CONFIGURATION PAGE #########################################################################################

namespace eval ::plugins::github::CFG {
	variable widgets
	array set widgets {}
		
	variable data
	array set data {
		page_name "::plugins::github::CFG"
		page_painted 0
		updating_list_msg {}
		plugins_list {}
		sel_plugin {}
		sel_plugin_desc {}
		sel_repo {}
		sel_name {}
		sel_installed_version {}
		sel_github_version {}
		sel_status {}
		sel_zipball_url {}
		sel_html_url {}
		sel_release_desc {}
		update_plugin_label {}
		update_plugin_msg {}
		restore_backup_msg {}
	}
}

# Added to context actions, so invoked automatically whenever the page is loaded
proc ::plugins::github::CFG::show_page {} {
	variable data
	variable widgets
	set ns [namespace current]

	if { ![ifexists data(page_painted) 0] } {
		::plugins::DGUI::set_scrollbars_dims $ns plugins_list
		::plugins::DGUI::relocate_text_wrt $widgets(updating_list_msg) $widgets(plugins_list) en 0 -25 e
	}
	
	::plugins::DGUI::hide_widgets "update_plugin* restore_backup* browse_release* whats_new*" $ns
	
	if { ![plugins enabled github]} {
		set data(sel_plugin_desc) [translate "Enable the plugin to show the list of available plugins."]
		::plugins::DGUI::hide_widgets "update_list*" $ns
		return
	}
	
	if { $data(page_painted) == 0 } {
		# Full list update first time we enter the page on each session
		update_list_click 1
		set data(page_painted) 1
	} else {
		update_list_click 0
	}

	plugins_list_select
}

proc ::plugins::github::CFG::setup_ui {} {
	variable widgets
	variable db
	set page [namespace current]

	# HEADER
	::plugins::DGUI::add_page $page -title [translate "GitHub Plugins Settings"] \
		-buttons_loc center -cancel_button 0 
	
	# Plugins listbox
	set x_left 150; set y 150
	::plugins::DGUI::add_listbox $page plugins_list $x_left $y $x_left [expr {$y+80}] 45 17 -label [translate Plugins] \
		-label_font_size $::plugins::DGUI::section_font_size 
 	bind $widgets(plugins_list) <<ListboxSelect>> ::plugins::github::CFG::plugins_list_select 
	
	::plugins::DGUI::add_variable $page [expr {$x_left+400}] $y updating_list_msg \
		-width 300 -justify right -font_size $::plugins::DGUI::section_font_size -fill $::plugins::DGUI::remark_color
	
	::plugins::DGUI::add_button3 $page update_list $x_left 1150 [translate "Update list"] sync \
		{::plugins::github::CFG::update_list_click 1} -width 400 -height 90
	
	# Selected plugin
	set x_right 1300; set y 220
	
	::plugins::DGUI::add_variable $page $x_right $y sel_plugin_desc -width 525 \
		-font_size $::plugins::DGUI::section_font_size
	
	::plugins::DGUI::add_text $page [expr {$x_right+75}] [expr {$y+200}] "\[ [translate {Browse release}] \]" \
		-font_size $::plugins::DGUI::section_font_size -widget_name browse_release \
		-has_button 1 -button_cmd ::plugins::github::CFG::browse_release_click -button_width 350
	::plugins::DGUI::add_text $page [expr {$x_right+550}] [expr {$y+200}] "\[ [translate {What's new?}] \]" \
		-font_size $::plugins::DGUI::section_font_size -widget_name whats_new \
		-has_button 1 -button_cmd ::plugins::github::CFG::whats_new_click -button_width 300
	
	
	# Update plugin button
	::plugins::DGUI::add_button2 $page update_plugin $x_right [incr y 350] "" "" cloud_download_alt \
		::plugins::github::CFG::update_plugin_click
	
	::plugins::DGUI::add_variable $page [expr {$x_right+$::plugins::DGUI::button2_width+60}] $y update_plugin_msg \
		-width 400 -fill $::plugins::DGUI::remark_color -font_size $::plugins::DGUI::section_font_size

	# Restore backup
	::plugins::DGUI::add_button2 $page restore_backup $x_right [incr y [expr {$::plugins::DGUI::button2_height+60}]] \
		[translate "Restore\rbackup"] "" trash_undo ::plugins::github::CFG::restore_backup_click
	
	::plugins::DGUI::add_variable $page [expr {$x_right+$::plugins::DGUI::button2_width+60}] $y restore_backup_msg \
		-width 400 -fill $::plugins::DGUI::remark_color -font_size $::plugins::DGUI::section_font_size
	
	# Footer warning
	::plugins::DGUI::add_text $page 1280 1350 [translate "Updates and new plugin installs direct from GitHub have not been tested by Decent.
They could potentially break the tablet app or introduce security problems. Install and use at your own risk."] \
		-width 1100 -anchor center -justify center -font_size [expr {$::plugins::DGUI::font_size-1}] \
		-fill $::plugins::DGUI::error_color
		
	::add_de1_action $page ::plugins::github::CFG::show_page
}

proc ::plugins::github::CFG::fill_plugins_listbox { {preserve_selection 1} {check_context 0} } {
	variable widgets
	variable data
	if { $check_context == 1 && $::de1(current_context) ne [namespace current] } { 
		return
	}
	if { $preserve_selection == 1 } {
		set sel_value [::plugins::DGUI::listbox_get_selection $widgets(plugins_list) $::plugins::github::settings(plugins)]
	} 

	foreach fn "plugins plugins_list sel_plugin sel_plugin_desc sel_repo sel_name sel_installed_version  
			sel_github_version sel_status sel_zipball_url sel_html_url sel_release_desc update_plugin_label" {
		set data($fn) {}
	}

	for { set i 0 } { $i < [llength $::plugins::github::settings(plugins)] } { incr i } {
		set item [lindex $::plugins::github::settings(names) $i]
		set status [lindex $::plugins::github::settings(status) $i]
		
		if { $status eq "uptodate" } {
			#append item " - up to date"
		} elseif { $status eq "install_available" } {
			append item " - available for install"
		} elseif { $status eq "update_available" } {
			append item " - update available"
		} 			
		lappend data(plugins_list) $item
	}
	
	if { $preserve_selection == 1 && $sel_value ne "" } {
		::plugins::DGUI::listbox_set_selection $widgets(plugins_list) $sel_value $::plugins::github::settings(plugins)
		plugins_list_select
	}
}

proc ::plugins::github::CFG::plugins_list_select {} {
	variable widgets
	variable data
	set ns [namespace current]

	foreach fn "sel_plugin sel_plugin_desc sel_repo sel_name sel_installed_version sel_github_version 
			sel_status sel_zipball_url sel_html_url sel_release_desc update_plugin_label" {
		set data($fn) {}
	}
	
	set data(sel_plugin_desc) {}
	set data(update_plugin_label) "" 
	
	set sel_idx [$widgets(plugins_list) curselection]
	if { $sel_idx eq "" } {
		::plugins::DGUI::hide_widgets "update_plugin* restore_backup*" $ns
	} else {
		set data(sel_plugin) [lindex $::plugins::github::settings(plugins) $sel_idx]
		set data(sel_repo) [lindex $::plugins::github::settings(repos) $sel_idx]
		set data(sel_zipball_url) [lindex $::plugins::github::settings(zipball_urls) $sel_idx]
		set data(sel_html_url) [lindex $::plugins::github::settings(html_urls) $sel_idx]
		
		set data(sel_name) [lindex $::plugins::github::settings(names) $sel_idx]
		set data(sel_installed_version) [lindex $::plugins::github::settings(installed_versions) $sel_idx]
		set data(sel_github_version) [lindex $::plugins::github::settings(github_versions) $sel_idx]
		set data(sel_status) [lindex $::plugins::github::settings(status) $sel_idx]
		set data(sel_release_desc) [lindex $::plugins::github::settings(release_descs) $sel_idx]
				
		set github_version_flags [lindex $::plugins::github::settings(github_versions_flags) $sel_idx]
		set published_at [lindex $::plugins::github::settings(published_at) $sel_idx]
		
		set desc "Plugin: $data(sel_name)\n"
		if { $data(sel_installed_version) eq "" } {
			append desc "Not installed\n"
		} else {
			append desc "Version installed: v$data(sel_installed_version)\n"
		}
		if { $data(sel_github_version) == -1 || $data(sel_github_version) eq "" } {
			append desc "GitHub version: Not found\n"
			::plugins::DGUI::hide_widgets "browse_release* whats_new*" $ns
		} else {
			append desc "GitHub version: v$data(sel_github_version)"
			if { $github_version_flags ne "" } {
				append desc " $github_version_flags"
			}
			if { $published_at ne "" } {
				if { [string is integer $published_at] } {
					append desc " ([clock format $published_at -format {%d %b %Y %H:%M}])"
				} else {
					append desc " ($published_at)"
				}
			}			
			append desc "\n"
			::plugins::DGUI::show_widgets "browse_release* whats_new*" $ns
		}		
		set data(sel_plugin_desc) $desc
		
		if { $data(sel_status) eq "update_available" } { 
			set data(update_plugin_label) [translate "Update\rplugin"]
			::plugins::DGUI::show_widgets "update_plugin*" $ns
 		} elseif { $data(sel_status) eq "install_available" } {
			set data(update_plugin_label) [translate "Install\rplugin"]
			::plugins::DGUI::show_widgets "update_plugin*" $ns
		} else {
			::plugins::DGUI::hide_widgets "update_plugin*" $ns
		}
		
		
		
		set plugin_backup_dir [::plugins::github::plugin_backup_dir $data(sel_plugin)]
		::plugins::DGUI::show_or_hide_widgets [file isdirectory $plugin_backup_dir] "restore_backup*" $ns
	}
}

proc ::plugins::github::CFG::update_list_click { {force_update 0} } {
	variable data	
	if { ![plugins enabled github] } return
	
	# Only requery list if it's empty, if the user has clicked the update button, or once a day.
	# There're request limits on GitHub API (https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting), 
	#	so we try not to hit it 
	set should_update [expr { [llength $::plugins::github::settings(plugins)] == 0 || \
		$::plugins::github::settings(plugins_last_update) eq "" || 
		([clock milliseconds] - $::plugins::github::settings(plugins_last_update)) > 86400000 }]
	
	if { $force_update == 1 || $should_update == 1 } {
		if { $::android == 1 && [borg networkinfo] eq "none" } {
			set data(updating_list_msg) [translate "No WiFi"]
		} else {
			set data(updating_list_msg) [translate "Updating list..."]
			::plugins::github::download_nondist_plugin_list
		}
		
		::plugins::github::load_nondist_plugin_list
		::plugins::github::update_list		
	}
	
	fill_plugins_listbox
	set data(updating_list_msg) ""
}

proc ::plugins::github::CFG::browse_release_click {} {
	variable data
	if { $data(sel_html_url) ne "" } {
		web_browser $data(sel_html_url) 
	}
}

proc ::plugins::github::CFG::whats_new_click {} {
	variable data
	if { $data(sel_release_desc) ne "" } {
		::plugins::DGUI::TXT::load_page "sel_release_desc" ::plugins::github::CFG::data(sel_release_desc) 1 \
			-page_title "[translate "What's new in $data(sel_name) v"]$data(sel_github_version)"
	}	
}

proc ::plugins::github::CFG::update_plugin_click {} {
	variable data
	if { $data(sel_plugin) eq "" } return
	
	if { $data(sel_status) eq "install_available" } {
		set data(update_plugin_msg) [translate "Installing plugin..."]
	} elseif { $data(sel_status) eq "update_available" } {
		set data(update_plugin_msg) [translate "Backing-up plugin..."]
		
		set plugin_backup_dir "[::plugins::github::plugin_backup_dir $data(sel_plugin)]"
		try {
			if { [file exists $plugin_backup_dir] } {
				file delete -force $plugin_backup_dir
			}		
			file copy -force "[::plugins::github::plugin_dir $data(sel_plugin)]" $plugin_backup_dir
		} on error err {
			msg -ERROR "saving plugin '$data(sel_plugin)' backup raised error: $err"
		}
		
		set data(update_plugin_msg) [translate "Updating plugin..."]
	} else {
		return
	}
	::plugins::DGUI::disable_widgets "update_plugin*" [namespace current]
	#update
		
	set plugin_updated [::plugins::github::update_plugin $data(sel_plugin) "" $data(sel_zipball_url) 1]
	
	if { $plugin_updated } {
		if { $data(sel_status) eq "install_available" } {
			set data(update_plugin_msg) "[translate {Plugin installed}]\r[translate {Please restart the app for changes to take effect}]"
		} elseif { $data(sel_status) eq "update_available" } {
			set data(update_plugin_msg) "[translate {Plugin updated}]\r[translate {Please restart the app for changes to take effect}]"
		}
		set data(sel_status) "uptodate"
		set data(sel_installed_version) $data(sel_github_version)
		
		set idx [lsearch $::plugins::github::settings(plugins) $data(sel_plugin)]
		if { $idx > -1 } {
			set ::plugins::github::settings(installed_versions) [lreplace \
				$::plugins::github::settings(installed_versions) $idx $idx $data(sel_github_version)]
			set ::plugins::github::settings(status) [lreplace \
				$::plugins::github::settings(installed_versions) $idx $idx "uptodate"]
		}
		
#		try {
#			plugins preload $data(sel_plugin)
#		} on error err {
#			append data(update_plugin_msg) "\rError preloading plugin: $err"
#		}
		
		after 3000 {
			set ::plugins::github::CFG::data(update_plugin_msg) ""
			::plugins::github::CFG::fill_plugins_listbox 1 1
		}
	} else {
		set data(update_plugin_msg) [translate "Installation error"]
	}
}

proc ::plugins::github::CFG::restore_backup_click {} {
	variable data
	if { $data(sel_plugin) eq "" } return
	set plugin_dir [::plugins::github::plugin_dir $data(sel_plugin)]
	set backup_dir [::plugins::github::plugin_backup_dir $data(sel_plugin)]
	
	if { [file isdirectory $backup_dir] } {
		set data(restore_backup_msg) [translate "Restoring backup..."]

		try {
			if { [file isdirectory $plugin_dir] } {
				foreach f [glob -directory $backup_dir -nocomplain *] {
					file copy -force $f $plugin_dir
				}
				file delete -force $backup_dir
			} else {
				file rename -force $backup_dir $plugin_dir
			}
		} on error err {
			set data(restore_backup_msg) [translate "Error restoring backup"]
			msg -ERROR "restore plugin '$data(sel_plugin)' backup error: $err"
			return
		}
	
		set data(restore_backup_msg) "[translate {Backup restored}]\r[translate {Please restart the app for changes to take effect}]"
		set data(sel_status) "uptodate"
		set data(sel_installed_version) ""
		
		set idx [lsearch $::plugins::github::settings(plugins) $data(sel_plugin)]
		if { $idx > -1 } {
			set ::plugins::github::settings(installed_versions) [lreplace \
				$::plugins::github::settings(installed_versions) $idx $idx ""]
			set ::plugins::github::settings(status) [lreplace \
				$::plugins::github::settings(installed_versions) $idx $idx "uptodate"]
		}
		
		after 3000 {
			set ::plugins::github::CFG::data(restore_backup_msg) ""
			::plugins::github::CFG::fill_plugins_listbox 1 1
		}
	} else {
		return
	}
}

proc ::plugins::github::CFG::page_done {} {
	say [translate {Done}] $::settings(sound_button_in)
	page_to_show_when_off extensions
}
