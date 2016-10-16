require 'rack_dav'
require 'listen'
require 'fileutils'
require 'rtesseract'
require 'shellwords'

raise 'INCOMING_PATH not specified' unless ENV['INCOMING_PATH']
raise 'PDF_PATH not specified' unless ENV['PDF_PATH']
raise 'STORAGE_PATH not specified' unless ENV['STORAGE_PATH']

INCOMING_PATH = ENV.fetch('INCOMING_PATH')
PDF_PATH = ENV.fetch('PDF_PATH')
STORAGE_PATH = ENV.fetch('STORAGE_PATH')

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
  grouped_files = files.group_by { |x| File.basename(x)[/[a-zA-Z]+/] }

  dir = File.join(STORAGE_PATH, Date.today.iso8601)
  FileUtils::mkdir_p dir

  grouped_files.each do |name, merge_files|
    file = File.join(dir, "#{name}.pdf")
    base_command = %w(gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite)
    output_file = "-sOutputFile=#{file}"
    command = Shellwords.join([*base_command, output_file, *merge_files])
    puts command
    %x[#{command}]
  end
end

merger

Signal.trap('USR1') do
  merger
end

use Rack::CommonLogger

run RackDAV::Handler.new(root: INCOMING_PATH)
