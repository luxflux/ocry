require 'rtesseract'
require 'mini_magick'

image = MiniMagick::Image.open('test.png')
image.resample(300)
image.write 'test_300dpi.png'
image = RTesseract.new("test_300dpi.png", processor: "mini_magick", lang: 'deu')
puts image.to_s

