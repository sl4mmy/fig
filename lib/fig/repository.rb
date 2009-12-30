require 'fig/parser'

module Fig
  class Repository
    def initialize(os, local_repository_dir, remote_repository_url, remote_repository_user=nil)
      @os = os
      @local_repository_dir = local_repository_dir
      @remote_repository_url = remote_repository_url
      @remote_repository_user = remote_repository_user
      @parser = Parser.new
    end

    def list_packages
      results = []
      @os.list(@local_repository_dir).each do |package_name|
        @os.list(File.join(@local_repository_dir, package_name)).each do |version_name|
          results << "#{package_name}/#{version_name}"
        end
      end
      results
    end

    def publish_package(package_statements, package_name, version_name) 
      temp_dir = temp_dir_for_package(package_name, version_name)
      @os.clear_directory(temp_dir)
      fig_file = File.join(temp_dir, ".fig")
      content = package_statements.map do |statement| 
        if statement.is_a?(Archive) || statement.is_a?(Resource)
          archive_name = statement.url.split("/").last
          archive_remote = "#{remote_dir_for_package(package_name, version_name)}/#{archive_name}"
          if is_url?(statement.url)
            archive_local = File.join(temp_dir, archive_name)
            @os.download(statement.url, archive_local)
          else
            archive_local = statement.url
          end
          @os.upload(archive_local, archive_remote, @remote_repository_user)
          statement.class.new(archive_name).unparse('')
        else
          statement.unparse('')
        end
      end
      @os.write(fig_file, content.join("\n"))
      @os.upload(fig_file, remote_fig_file_for_package(package_name, version_name), @remote_repository_user)
      update_package(package_name, version_name)
    end

    def load_package(package_name, version_name)
      update_package(package_name, version_name) if @remote_repository_url
      read_local_package(package_name, version_name)
    end

    def update_package(package_name, version_name)
      remote_fig_file = remote_fig_file_for_package(package_name, version_name)
      local_fig_file = local_fig_file_for_package(package_name, version_name)
      if @os.download(remote_fig_file, local_fig_file)
        install_package(package_name, version_name)
      end
    end

    def read_local_package(package_name, version_name)
      dir = local_dir_for_package(package_name, version_name)
      read_package_from_directory(dir, package_name, version_name)
    end 

    def read_remote_package(package_name, version_name)
      url = remote_fig_file_for_package(package_name, version_name)
      content = @os.read_url(url)
      @parser.parse_package(package_name, version_name, nil, content)
    end

    def read_package_from_directory(dir, package_name, version_name)
      read_package_from_file(File.join(dir, ".fig"), package_name, version_name)
    end

    def read_package_from_file(file_name, package_name, version_name)
      raise "Package not found: #{file_name}" unless @os.exist?(file_name)
      modified_time = @os.mtime(file_name)
      content = @os.read(file_name)
      @parser.parse_package(package_name, version_name, File.dirname(file_name), content)
    end

    def local_dir_for_package(package_name, version_name)
      File.join(@local_repository_dir, package_name, version_name)
    end

  private

    def install_package(package_name, version_name)
      begin
        package = read_local_package(package_name, version_name)
        temp_dir = temp_dir_for_package(package_name, version_name)
        @os.clear_directory(temp_dir)
        package.archive_urls.each do |archive_url|
          if not is_url?(archive_url)
            archive_url = remote_dir_for_package(package_name, version_name) + "/" + archive_url
          end
          @os.download_archive(archive_url, File.join(temp_dir))
        end
        package.resource_urls.each do |resource_url|
          if not is_url?(resource_url)
            resource_url = remote_dir_for_package(package_name, version_name) + "/" + resource_url
          end
          @os.download_resource(resource_url, File.join(temp_dir))
        end
        local_dir = local_dir_for_package(package_name, version_name)
        @os.clear_directory(local_dir)
        # some packages contain no files, only a fig file.
        if not (package.archive_urls.empty? && package.resource_urls.empty?)
          @os.exec(temp_dir, "mv * #{local_dir}/")
        end
        write_local_package(package_name, version_name, package)
      rescue
        $stderr.puts "install failed, cleaning up" 
        delete_local_package(package_name, version_name)
        raise
      end
    end

    def is_url?(url)
      not (/ftp:\/\/|http:\/\/|file:\/\/|ssh:\/\// =~ url).nil?
    end

    def delete_local_package(package_name, version_name)
      FileUtils.rm_rf(local_dir_for_package(package_name, version_name))
    end

    def write_local_package(package_name, version_name, package)
      file = local_fig_file_for_package(package_name, version_name)
      @os.write(file, package.unparse)
    end

    def remote_fig_file_for_package(package_name, version_name)
      "#{@remote_repository_url}/#{package_name}/#{version_name}/.fig"
    end  

    def local_fig_file_for_package(package_name, version_name)
      File.join(local_dir_for_package(package_name, version_name), ".fig")
    end

    def remote_dir_for_package(package_name, version_name)
      "#{@remote_repository_url}/#{package_name}/#{version_name}"
    end

    def temp_dir_for_package(package_name, version_name)
      File.join(@local_repository_dir, "tmp")
    end
  end
end