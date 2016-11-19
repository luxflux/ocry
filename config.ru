require 'rack_dav'
require 'listen'
require 'fileutils'
require 'rtesseract'
require 'shellwords'
require 'rugged'
require 'logger'

%w(INCOMING_PATH PDF_PATH STORAGE_PATH GIT_REPO HTTP_USER HTTP_PASSWORD).each do |variable|
  raise "#{variable} not specified" unless ENV[variable]
end

INCOMING_PATH = ENV.fetch('INCOMING_PATH')
PDF_PATH = ENV.fetch('PDF_PATH')
STORAGE_PATH = ENV.fetch('STORAGE_PATH')
GIT_REPO = ENV.fetch('GIT_REPO')
USER = { email: 'root@yux.ch', name: 'ocry', time: Time.now }
HTTP_USER = ENV.fetch('HTTP_USER')
HTTP_PASSWORD = ENV.fetch('HTTP_PASSWORD')

FileUtils::mkdir_p INCOMING_PATH
FileUtils::mkdir_p PDF_PATH

LOGGER = Logger.new('ocry.log')
LOGGER.info 'starting up...'
$stdout.reopen(File.open('ocry.stdout.log', 'a+'))
$stderr.reopen(File.open('ocry.stderr.log', 'a+'))

def process(file)
  LOGGER.info "Processing #{file}"
  image = RTesseract.new(file, lang: 'deu+eng', processor: 'mini_magick')
  pdf_path = image.to_pdf
  new_file = File.join(PDF_PATH, "#{File.basename(file)}.pdf")
  FileUtils.mv(pdf_path, new_file)
  LOGGER.info "Created #{new_file}"
  new_file

  LOGGER.info "Removing #{file}"
  File.unlink file
end

listener = Listen.to(INCOMING_PATH) do |modified, added, removed|
  LOGGER.debug "Modified: #{modified}"
  LOGGER.debug "Added: #{added}"
  LOGGER.debug "Removed: #{removed}"

  if added.any?
    pdfs = added.map do |file|
      process(file)
    end
  end
end
listener.start

def grouped_files
  files = Dir.glob("#{PDF_PATH}/**/*.pdf")
  LOGGER.debug files
  return {} unless files.any?
  files.group_by { |x| File.basename(x)[/[a-zA-Z ]+/].gsub(' Seite ', '').strip }
end

def merger
  dir = File.join(STORAGE_PATH, Date.today.iso8601)
  FileUtils::mkdir_p dir

  grouped_files.each do |name, merge_files|
    file = File.join(dir, "#{name}.pdf")
    if File.exists?(file)
      LOGGER.info "#{file} already exists, won't merge #{merge_files.join(',')} into #{file}"
    else
      LOGGER.info "Merging #{merge_files.join(',')} into #{name}"
      base_command = %w(gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite)
      output_file = "-sOutputFile=#{file}"
      command = Shellwords.join([*base_command, output_file, *merge_files])
      LOGGER.info command
      %x[#{command}]
    end

    merge_files.each do |file|
      LOGGER.info "Removing file #{file}"
      File.unlink file
    end
  end
end

def committer
  repo = Rugged::Repository.new(STORAGE_PATH)
  changes = false
  repo.status { changes = true }
  return unless changes

  index = repo.index
  index.add_all
  options = {
    tree: index.write_tree(repo),
    author: USER,
    comitter: USER,
    message: 'Automagic update after PDF processing',
    parents: repo.empty? ? [] : [ repo.head.target ].compact,
    update_ref: 'HEAD',
  }
  Rugged::Commit.create(repo, options)
  index.write
  repo.push('origin', ['refs/heads/master'])
end

unless Dir.exists?(STORAGE_PATH)
  Rugged::Repository.clone_at(GIT_REPO, STORAGE_PATH)
end

Signal.trap('USR1') do
  process.call
end

index = lambda do |env|
  Rack::Response.new(ERB.new(File.read('index.html.erb')).result(binding))
end

process = lambda do |env|
  merger
  committer
  res = Rack::Response.new
  res.redirect('/')
  res.finish
end

use Rack::CommonLogger, LOGGER
map '/webdav' do
  use Rack::Auth::Basic, 'Bill Uploader' do |username, password|
    Rack::Utils.secure_compare(HTTP_USER, username) && Rack::Utils.secure_compare(HTTP_PASSWORD, password)
  end
  run RackDAV::Handler.new(root: INCOMING_PATH)
end
map '/process' do
  run process
end
map '/' do
  run index
end

LOGGER.info 'startup complete...'
