require 'chef/knife'
require 'chef/cookbook_loader'
require 'chef/cookbook_uploader'
require 'grit'

module CookbookBump
  class Bump < Chef::Knife

    TYPE_INDEX = { "major" => 0, "minor" => 1, "patch" => 2 }
    TYPE_INDEX_2 = { "specific" => 3, "round" => 5 }

    banner "knife bump COOKBOOK [MAJOR|MINOR|PATCH|SPECIFIC x.x.x|ROUND <MAJOR|MINOR>']"


    def run
  
      self.config = Chef::Config.merge!(config)
      if config.has_key?(:cookbook_path)
        cookbook_path = config["cookbook_path"]
      else
        ui.fatal "No default cookbook_path; Specify with -o or fix your knife.rb."
        show_usage
        exit 1
      end
      
      if name_args.size == 0
        show_usage
        exit 0
      end

      unless name_args.size == 2 or name_args.size == 3
        ui.fatal "Please specify the cookbook whose version you which to bump, and the type of bump you wish to apply."
        show_usage
        exit 1
      end
      unless name_args.size == 3
        unless TYPE_INDEX.has_key?(name_args.last.downcase)
          ui.fatal "Sorry, '#{name_args.last}' isn't a valid bump type.  Specify one of 'major', 'minor','patch', 'specific x.x.x', 'round <major|minor>'"
          show_usage
          exit 1
        end
        patch_type = name_args.last
        patch_mode = 1
      else
        unless TYPE_INDEX_2.has_key?(name_args[-2].downcase)
          ui.fatal "Sorry, '#{name_args[-2]}' isn't a valid bump type.  Specify one of 'major', 'minor','patch', 'specific x.x.x', 'round <major|minor>'"
          show_usage
          exit 1
        end
	patch_type = name_args[-2]
        specific_version = name_args.last
        patch_mode = 2
      end
      cookbook = name_args.first
      
      cookbook_paths = Array(config[:cookbook_path])
      cookbook_path = which_path(cookbook_paths,cookbook)

      patch(cookbook_path, cookbook, patch_type) if patch_mode == 1
      patch_specific(cookbook_path, cookbook, specific_version) if patch_mode == 2
      
    end
    
    def which_path(cookbook_paths,cookbook)
      cookbook_paths.each do | path |
	if File.exists?("#{path}/#{cookbook}")
          ui.msg("Cookbook in #{path}")
	  return path
        end
      end
    end

    def patch(cookbook_path, cookbook, type)
      t = TYPE_INDEX[type] 
      current_version = get_version(cookbook_path, cookbook).split(".").map{|i| i.to_i}
      bumped_version = current_version.clone
      bumped_version[t] = bumped_version[t] + 1
      metadata_file = File.join(cookbook_path, cookbook, "metadata.rb")
      old_version = current_version.join('.')
      new_version = bumped_version.join('.') 
      update_metadata(old_version, new_version, metadata_file)
      ui.msg("Bumping #{type} level of the #{cookbook} cookbook from #{old_version} to #{new_version}")
    end

    def patch_specific(cookbook_path, cookbook, specific_version)
      if specific_version == "major" || specific_version == "minor" || specific_version == "patch"
	patch_round(cookbook_path, cookbook, specific_version)
      else
        old_version = get_version(cookbook_path, cookbook)
        new_version = specific_version
        metadata_file = File.join(cookbook_path, cookbook, "metadata.rb")
        update_metadata(old_version, new_version, metadata_file)
        ui.msg("Setting the version of the #{cookbook} cookbook to #{new_version}")
      end
    end

    def patch_round(cookbook_path, cookbook, specific_version)
      t = TYPE_INDEX[specific_version] 
      current_version = get_version(cookbook_path, cookbook).split(".").map{|i| i.to_i}
      bumped_version = current_version.clone
      bumped_version[t] = bumped_version[t] + 1
      if t == 0 
      	bumped_version[t+1] = 0
        bumped_version[t+2] = 0
      elsif t == 1
        bumped_version[t+1] = 0
      else
	ui.msg("")
        ui.fatal "Sorry, '#{name_args[-3]}' isn't a valid bump type.  Specify one of 'major', 'minor','patch', 'specific x.x.x', 'round <major|miner>'"
        show_usage
        exit 1
      end

      metadata_file = File.join(cookbook_path, cookbook, "metadata.rb")
      old_version = current_version.join('.')
      new_version = bumped_version.join('.') 
      update_metadata(old_version, new_version, metadata_file)
      ui.msg("Bumping to next #{specific_version} and rounding the level of the #{cookbook} cookbook from #{old_version} to #{new_version}")
    end

    def update_metadata(old_version, new_version, metadata_file)
      open_file = File.open(metadata_file, "r")
      body_of_file = open_file.read
      open_file.close
      body_of_file.gsub!(old_version, new_version)
      File.open(metadata_file, "w") { |file| file << body_of_file }
    end
    
    def get_version(cookbook_path, cookbook)
      loader = ::Chef::CookbookLoader.new(cookbook_path)
      return loader[cookbook].version
    end

    def get_tags(cookbook_path, cookbook)
      git_repo = find_git_repo(cookbook_path, cookbook)
      g = Grit::Repo.new(git_repo)
      if g.config["remote.origin.url"].split(File::SEPARATOR).last.scan(cookbook).size > 0
        ui.confirm("I found a repo at #{git_repo} - do you want to tag it?")
      else
        ui.confirm("I didn't find a repo with a name like #{cookbook}.  I did find #{git_repo} - are you sure you want to tag it?")
      end
      g.tags.map { |t| t.name }
    end

    def tag
    end

    def find_git_repo(cookbook_path, cookbook)
      loader = ::Chef::CookbookLoader.new(cookbook_path)
      cookbook_dir = loader[cookbook].root_dir
      full_path = cookbook_dir.split(File::SEPARATOR)
      (full_path.length - 1).downto(0) do |search_path_index|
        git_config = File.join(full_path[0..search_path_index] + [".git", "config"])
        if File.exist?(git_config)
          return File.join(full_path[0..search_path_index])
        end
      end
      ui.fatal("Unable to find a git repo for this cookbook.")
    end
  end
end
