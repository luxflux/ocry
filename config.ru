require 'rack_dav'
require 'listen'
require 'fileutils'
require 'rtesseract'
require 'shellwords'
require 'rugged'

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

def process(file)
  puts "Processing #{file}"
  image = RTesseract.new(file, lang: 'deu+eng', processor: 'mini_magick')
  pdf_path = image.to_pdf
  new_file = File.join(PDF_PATH, "#{File.basename(file)}.pdf")
  FileUtils.mv(pdf_path, new_file)
  puts "Created #{new_file}"
  new_file
end

listener = Listen.to(INCOMING_PATH) do |modified, added, removed|
  puts "Modified: #{modified}"
  puts "Added: #{added}"
  puts "Removed: #{removed}"

  if added.any?
    pdfs = added.map do |file|
      process(file)
    end
  end
end
listener.start

def merger
  files = Dir.glob("#{PDF_PATH}/**/*.pdf")
  return unless files.any?
  grouped_files = files.group_by { |x| File.basename(x)[/[a-zA-Z]+/] }

  dir = File.join(STORAGE_PATH, Date.today.iso8601)
  FileUtils::mkdir_p dir

  grouped_files.each do |name, merge_files|
    file = File.join(dir, "#{name}.pdf")
    next if File.exists?(file)
    base_command = %w(gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite)
    output_file = "-sOutputFile=#{file}"
    command = Shellwords.join([*base_command, output_file, *merge_files])
    puts command
    %x[#{command}]
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
  repo.push('origin')
end

unless Dir.exists?(STORAGE_PATH)
  Rugged::Repository.clone_at(GIT_REPO, STORAGE_PATH)
end

merger

Signal.trap('USR1') do
  merger
  committer
end

use Rack::CommonLogger
use Rack::Auth::Basic, 'Bill Uploader' do |username, password|
  Rack::Utils.secure_compare(HTTP_USER, username) && Rack::Utils.secure_compare(HTTP_PASSWORD, password)
end
run RackDAV::Handler.new(root: INCOMING_PATH)
