use Image::RGBA::Text;

my constant RGBA = Image::RGBA::Text;
sub dump(|c) { .dump(|c) for RGBA.parse($*ARGFILES) }

sub meta is export { dump :meta  }
sub raw is export  { dump :raw   }
sub t32 is export  { dump :32bit }
sub t24 is export  { dump :24bit }
sub t16 is export  { dump :16bit }
sub t12 is export  { dump :12bit }
sub t8  is export  { dump :8bit  }
sub t4  is export  { dump :4bit  }
