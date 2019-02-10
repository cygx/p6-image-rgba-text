use lib 'lib';
use Test;
use Image::RGBA::Text;

plan 2;

my $img = RGBAText.decode: q:to/END/;
    =rgba 1 1
    =meta foo 1234
    =meta bar a b c
    0
    END

is $img.meta<foo>, '1234';
is $img.meta<bar>, 'a b c';
