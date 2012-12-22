#
# Cookbook Name:: artifact
# Provider:: deploy
#
# Author:: Jamie Winsor (<jamie@vialstudios.com>)
# Copyright 2012, Riot Games
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'pathname'
require 'uri'
require 'yaml'

attr_reader :release_path
attr_reader :current_path
attr_reader :shared_path
attr_reader :previous_release_path
attr_reader :artifact_root
attr_reader :version_container_path
attr_reader :manifest_file
attr_reader :previous_versions
attr_reader :actual_version

def load_current_resource
  if @new_resource.artifact_url
    Chef::Log.warn "[artifact] 'artifact_url' is deprecated, please use 'artifact_location' instead."
    @new_resource.artifact_location = @new_resource.artifact_url
  end

  unless @new_resource.version
    Chef::Application.fatal! "You must specify a version for artifact '#{@new_resource.name}'!"
  end

  if latest?(@new_resource.version) && from_http?(@new_resource.artifact_location)
    Chef::Application.fatal! "You cannot specify the latest version for an artifact when attempting to download an artifact using http!"
  end
  
  run_context.include_recipe "nexus::cli"

  @actual_version         = Chef::Artifact.get_actual_version(node, @new_resource.artifact_location, @new_resource.version)
  @release_path           = get_release_path
  @current_path           = @new_resource.current_path
  @shared_path            = @new_resource.shared_path
  @artifact_root          = ::File.join(@new_resource.artifact_deploy_path, @new_resource.name)
  @version_container_path = ::File.join(@artifact_root, actual_version)
  @previous_release_path  = get_previous_release_path
  @previous_versions      = get_previous_versions
  @manifest_file          = ::File.join(@release_path, "manifest.yaml")
  @current_resource       = Chef::Resource::ArtifactDeploy.new(@new_resource.name)

  @current_resource
end

action :deploy do
  next unless new_resource.force or not deployed?

  delete_previous_versions(:keep => new_resource.keep)

  recipe_eval do
    setup_deploy_directories!
    setup_shared_directories!

    retrieve_artifact!

    recipe_eval(&new_resource.before_extract) if new_resource.before_extract

    if new_resource.is_tarball
      extract_artifact
    else
      copy_artifact
    end
  end

  recipe_eval(&new_resource.before_symlink) if new_resource.before_symlink

  recipe_eval do
    symlink_it_up!
  end

  recipe_eval(&new_resource.before_migrate) if new_resource.before_migrate
  recipe_eval(&new_resource.migrate) if new_resource.should_migrate
  recipe_eval(&new_resource.after_migrate) if new_resource.after_migrate

  recipe_eval do
    link new_resource.current_path do
      to release_path
      user new_resource.owner
      group new_resource.group
    end
  end

  recipe_eval(&new_resource.restart_proc) if new_resource.restart_proc

  recipe_eval { write_manifest(create_manifest(release_path)) }

  new_resource.updated_by_last_action(true)
end

def extract_artifact
  execute "extract_artifact" do
    command "tar xzf #{cached_tar_path} -C #{release_path}"
    user new_resource.owner
    group new_resource.group
  end
end

def copy_artifact
  execute "copy artifact" do
    command "cp #{cached_tar_path} #{release_path}"
    user new_resource.owner
    group new_resource.group
  end
end

def cached_tar_path
  ::File.join(version_container_path, artifact_filename)
end

def artifact_filename
  if from_nexus?(new_resource.artifact_location)
    group_id, artifact_id, version, extension = new_resource.artifact_location.split(":")
    unless extension
      extension = "jar"
    end
    if latest?(version)
      version = actual_version
    end
    "#{artifact_id}-#{version}.#{extension}"
  else
    ::File.basename(new_resource.artifact_location)
  end
end

private

  def delete_previous_versions(options = {})
    keep = options[:keep] || 0
    delete_first = total = previous_versions.length

    if total == 0 || total <= keep
      return true
    end

    delete_first -= keep

    Chef::Log.info "artifact_deploy[delete_previous_versions] is deleting #{delete_first} of #{total} old versions (keeping: #{keep})"

    to_delete = previous_versions.shift(delete_first)

    to_delete.each do |version|
      delete_cached_files_for(version.basename)
      delete_release_path_for(version.basename)
      Chef::Log.info "artifact_deploy[delete_previous_versions] #{version.basename} deleted"
    end
  end

  def delete_cached_files_for(version)
    FileUtils.rm_rf ::File.join(artifact_root, version)
  end

  def delete_release_path_for(version)
    FileUtils.rm_rf ::File.join(new_resource.deploy_to, 'releases', version)
  end

  def deployed?
    if get_previous_release_version != new_resource.version
      Chef::Log.info "No current version installed for #{new_resource.name}." if get_previous_release_version.nil?
      Chef::Log.info "Currently installed version of artifact is #{get_previous_release_version}." unless get_previous_release_version.nil?
      Chef::Log.info "Installing version, #{actual_version} for #{new_resource.name}."
      return false 
    end
    if previous_release_path.nil? || !::File.exists?(::File.join(previous_release_path, "manifest.yaml"))
      Chef::Log.warn "No manifest file found for current version, deploying anyway."
      return false
    end
    Chef::Log.info "Loading manifest.yaml file from directory: #{previous_release_path}"
    original_manifest = YAML.load_file(::File.join(previous_release_path, "manifest.yaml"))    
    
    current_manifest = create_manifest(current_path)
    differences = original_manifest.find do |key, value|
      !current_manifest.has_key?(key) || value != current_manifest[key]
    end
    if differences
      Chef::Log.info "Differences found between the saved manifest at directory: #{previous_release_path} and manifest created from files at: #{current_path}. Redepoying."
      return false
    else
      return true
    end
  end

  def get_previous_release_path
    if ::File.exists?(current_path)
      ::File.readlink(current_path)
    end
  end

  def get_previous_release_version
    if ::File.exists?(current_path)
      ::File.basename(get_previous_release_path)
    end
  end

  def get_release_path
    ::File.join(new_resource.deploy_to, "releases", actual_version)
  end

  def get_previous_versions
    versions = Dir[::File.join(artifact_root, '**')].collect do |v|
      Pathname.new(v)
    end

    versions.reject! { |v| v.to_s == version_container_path }

    versions.sort_by(&:mtime)
  end

  def symlink_it_up!
    new_resource.symlinks.each do |key, value|
      directory "#{new_resource.shared_path}/#{key}" do
        owner new_resource.owner
        group new_resource.group
        mode '0755'
        recursive true
      end

      link "#{release_path}/#{value}" do
        to "#{new_resource.shared_path}/#{key}"
        owner new_resource.owner
        group new_resource.group
      end
    end
  end

  def setup_deploy_directories!
    [ version_container_path, release_path, shared_path ].each do |path|
      directory path do
        owner new_resource.owner
        group new_resource.group
        mode '0755'
        recursive true
      end
    end
  end

  def setup_shared_directories!
    new_resource.shared_directories.each do |dir|
      directory "#{shared_path}/#{dir}" do
        owner new_resource.owner
        group new_resource.group
        mode '0755'
        recursive true
      end
    end
  end

  def retrieve_artifact!
    if from_http?(new_resource.artifact_location)
      retrieve_from_http
    elsif from_nexus?(new_resource.artifact_location)
      retrieve_from_nexus
    elsif ::File.exist?(new_resource.artifact_location)
      retrieve_from_local
    else
      raise "Cannot retrieve artifact #{new_resource.artifact_location}! Please make sure the artifact exists in the specified location."
    end
  end

  def from_http?(location)
    location =~ URI::regexp(['http', 'https'])
  end

  def from_nexus?(location)
    location.split(":").length > 3
  end

  def latest?(version)
    version.casecmp("latest") == 0
  end

  def retrieve_from_http
    remote_file cached_tar_path do
      source new_resource.artifact_location
      owner new_resource.owner
      group new_resource.group
      checksum new_resource.artifact_checksum
      backup false

      action :create
    end
  end

  def retrieve_from_nexus

    ruby_block "retrieve from nexus" do
      block do
        require 'nexus_cli'

        unless ::File.exists?(cached_tar_path) && Chef::ChecksumCache.checksum_for_file(cached_tar_path) == new_resource.artifact_checksum
          config = Chef::Artifact.nexus_config_for(node)
          remote = NexusCli::RemoteFactory.create(config, false)
          remote.pull_artifact(new_resource.artifact_location, version_container_path)
        end
      end
    end
  end

  def retrieve_from_local
    file cached_tar_path do
      content ::File.open(new_resource.artifact_location).read
      owner new_resource.owner
      group new_resource.group
    end
  end

  def create_manifest(files_path)
    require 'digest'
    files_in_release_path = nil
    Dir.chdir(files_path) do |path|
      files_in_release_path = Dir.glob("**/*").reject { |file| ::File.directory?(file) || file == "manifest.yaml" }
    end
    
    files_in_release_path.inject(Hash.new) do |map, file|
      map[file] = Digest::SHA1.hexdigest(file)
      map
    end
  end

  def write_manifest(manifest)
    require 'yaml'
    Chef::Log.info "Writing manifest.yaml file to #{manifest_file}"
    ::File.open(manifest_file, "w") { |file| file.puts YAML.dump(manifest) }
  end
