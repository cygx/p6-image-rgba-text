# Copyright 2015 cygx <cygx@cpan.org>
# Distributed under the Boost Software License, Version 1.0

=begin pod

=head1 Image::RGBA::Text format

C<Image::RGBA::Text> allows you to create images with 32 bits per pixel color
depth with Red, Green, Blue, and Alpha channels.

An input document can contain one or multiple images. Calling C<RGBAText.decode>
with the C<:all> named parameter will return all images as a list, otherwise
only the first image will be returned.

Input documents are simply a sequence of lines (determined by what the C<lines>
method of the source that is passed to the C<decode> function returns) that are
either directives or pixel data.

=head2 Directives

=head3 C<=rgba>

The C<=rgba> directive starts a new image. The directive itself is followed by
two numbers (digits conforming to C<\d> in regex language, and anything that is
supported by Perl 6's C<Int> method on C<Str>) and a free text that will be
stored in the C<info> attribute of the image object. The two numbers specify
the width and height of the image respectively. That is, the first number
specifies how many pixels are in each line of the resulting image and the
second number specifies how many lines will be expected.

=head3 C<=map>

The C<=map> directive sets up "names" for colors that can be used in the pixel
data portion of the image. It accepts a list of twos where the first entry is
the name that should be available in the pixel data portion and the second
entry is a color value as explained in the section L<Colors>.

A map directive only influences pixel data following in the input file, and
mappings are reset whenever a C<=rgba> directive is encountered.

Multiple map directives in a row are equivalent to a single map directive
containing the first directive's mappings followed by the second map
directive's mappings etc.

=head3 C<=scale>

The C<=scale> directive is followed by a single number that specifies the
default scaling factor that will be used by the image if C<.scale> is called
on it with no argument.

=head2 Pixel Data

Any line that doesn't start with a C<=> character will be interpreted as pixel
data. Every line of pixel data contains one or more space-separated "names" for
colors that will be put into the resulting image.

The lines don't have to be contain as many entries as the image is wide, but
supplying less than a whole line's worth will not fill up the rest of the
line in the image with pixels. Instead, all pixel data is interpreted the same
way as if they were in one long line: The first C<N> entries will be used for
the first line, the next C<N> entries for the second line, and so on.

=head3 Colors

C<Image::RGBA::Text> understands six different ways to specify colors. They
are distinguished by the number of characters in each piece.

=head4 A single hexadecimal digit

C<Image::RGBA::Text> comes with a default palette for single hexadecimal digits:

    #000000FF 0
    #7F0000FF 1
    #007F00FF 2
    #7F7F00FF 3
    #00007FFF 4
    #7F007FFF 5
    #007F7FFF 6
    #7F7F7FFF 7
    #00000000 8
    #FF0000FF 9
    #00FF00FF A
    #FFFF00FF B
    #0000FFFF C
    #FF00FFFF D
    #00FFFFFF E
    #FFFFFFFF F

In words, numbers 0 through 7 are black and dark colors, all opaque. Number 8
is a transparent black pixel. Numbers 9 through F are bright colors followed
by white.

=head4 Double hexadecimal digits

Double hexadecimal digits, i.e. 00 through FF, will result in a greyscale of
opaque pixels. 00 is black, FF is white, the values in between just have the
given hexadecimal number for the R, G, B channels and FF for the alpha channel.

=head4 Three hexadecimal digits

Three hexadecimal digits will result in opaque pixels where the individual
hexadecimal digits are doubled and stored as the R, G, and B value
respectively. For example, the value C<47e> would result in the RGBA color
value C<#4477eeFF>.

=head4 Four hexadecimal digits

This works the same way as three hexadecimal digits, but the alpha channel
takes its value from the fourth digit rather than being fixed at FF.

=head4 Six hexadecimal digits

Six hexadecimal digits work exactly like you would expect from HTML, CSS,
or graphics software in general: The first two digits are for the red
channel, the next two for the green channel, and the last two for the blue
channel. The alpha channel is always FF.

=head4 Eight hexadecimal digits

This works the same way as six hexadecimal digits, but the last two digits
are used for the alpha channel.

=head3 Comments

Any line that doesn't start with a C<=> character can have a C<#> sign that
indicates the start of a comment. Comments can be followed by any text and
will be stored in the image object's C<comments> attribute as a list of pairs
with the key being the X and Y position where the comment was started and the
value being the text.

=end pod

unit class RGBAText is export;

has blob8 $.bytes;
has uint  $.width;
has uint  $.height;
has Str   $.info;
has Int   $.default-scale is rw = 1;

has @.comments;
has %.mappings;
has %.revmap = <
    000000FF 0
    7F0000FF 1
    007F00FF 2
    7F7F00FF 3
    00007FFF 4
    7F007FFF 5
    007F7FFF 6
    7F7F7FFF 7
    00000000 8
    FF0000FF 9
    00FF00FF A
    FFFF00FF B
    0000FFFF C
    FF00FFFF D
    00FFFFFF E
    FFFFFFFF F
>;

sub set-elems(\obj, \elems) {
    use nqp;
    nqp::setelems(obj, elems);
}

method unbox { $!bytes, $!width, $!height }

method box(RGBAText:U: blob8 $bytes, UInt $width, UInt $height) {
    self.bless(:$bytes, :$width, :$height);
}

method decode(RGBAText:U: $src, Bool :$all) {
    my ($img, $bytes);
    my $N = -1;
    my $n = 0;

    my grammar Line {
        token TOP {
            [   <.header>
            |   <.map>
            |   <.scale>
            |   <.pixels>? \h* <.comment>?
            ]
        }

        token header {
            '=rgba' \h+ (\d+) \h+ (\d+) [ \h+ (.*) ]?
        }

        token scale {
            '=scale' <?{ defined $img }> \h+ (\d+)
        }

        token map {
            '=map' <?{ defined $img }> [ \h+ (\H+) \h+ (<.xdigit>+) ]+
        }

        token comment {
            '#' <?{ defined $img }> \h* (.*)
        }

        token pixels {
            <![=#]> <?{ defined $img }> \h* (<-[\h#]>+)+ %% \h+
        }
    }

    my $actions = class {
        method header($/) {
            my $width = +$0;
            my $height = +$1;
            my $info = $2 ?? ~$2 !! '';

            $bytes := buf8.new;
            $N = $width * $height * 4;

            $bytes.&set-elems($N);
            $img = RGBAText.new(:$width, :$height, :$info, :$bytes);
        }

        sub expand($key, $value) {
            my &convert1 = { (:16($_) // return Empty).base(16) x 2 }
            my &convert2 = { sprintf '%02X', (:16($_) // return Empty) };

            given $value.chars {
                when 1 {
                    my \iv = :16($value) // return Empty;
                    my \dark = !(iv +& 8);
                    sprintf(
                        '%02X%02X%02X%02X',
                        0xFF * ?(iv +& 1) +> dark,
                        0xFF * ?(iv +& 2) +> dark,
                        0xFF * ?(iv +& 4) +> dark,
                        0xFF * !(iv == 8)
                    ) => $key;
                }

                when 2 { convert2($value) x 3 ~ 'FF' => $key; }
                when 3 { $value.comb.map(&convert1).join ~ 'FF' => $key }
                when 4 { $value.comb.map(&convert1).join => $key }
                when 6 { $value.comb.map(&convert2).join ~ 'FF' => $key }
                when 8 { $value.comb.map(&convert2).join => $key }

                default { Empty }
            }
        }

        method map($/) {
            my @keys = ~<<$0;
            my @values = ~<<$1;
            $img.mappings{@keys} = @values;
            $img.revmap{.key} = .value
                for (flat @keys Z @values).map: &expand;
        }

        method scale($/) {
            my $scale = +$0.Str;
            $img.default-scale = $scale if $scale > 1;
        }

        method comment($/) {
            my $i = $n div 4;
            $img.comments.push(
                ($i mod $img.width, $i div $img.width) => ~$0);
        }

        method pixels($/) {
            for $0>>.Str {
                my $value = $img.mappings{$_} // $_;
                given $value.chars {
                    when 1 {
                        my \iv = :16($value) // return $img = Nil;
                        my \dark = !(iv +& 8);

                        $bytes[$n++] = 0xFF * ?(iv +& 1) +> dark;
                        $bytes[$n++] = 0xFF * ?(iv +& 2) +> dark;
                        $bytes[$n++] = 0xFF * ?(iv +& 4) +> dark;
                        $bytes[$n++] = 0xFF * !(iv == 8);
                    }

                    when 2 {
                        my \iv = :16($value) // return $img = Nil;
                        $bytes[$n++] = iv;
                        $bytes[$n++] = iv;
                        $bytes[$n++] = iv;
                        $bytes[$n++] = 0xFF;
                    }

                    when 3 {
                        $bytes[$n++] = 0x11 * (:16($_) // return $img = Nil)
                            for $value.comb;

                        $bytes[$n++] = 0xFF;
                    }

                    when 4 {
                        $bytes[$n++] = 0x11 * (:16($_) // return $img = Nil)
                            for $value.comb;
                    }

                    when 6 {
                        $bytes[$n++] = (:16($_) // return $img = Nil)
                            for $value.comb(2);

                        $bytes[$n++] = 0xFF;
                    }

                    when 8 {
                        $bytes[$n++] = (:16($_) // return $img = Nil)
                            for $value.comb(2);
                    }

                    default { return $img = Nil }
                }
            }
        }
    }

    my $ll := gather for $src.lines {
        Line.parse($_, :$actions);
        if $n == $N {
            take $img;
            $img = Nil;
            $N = -1;
            $n = 0;
        }
    }

    if $all { $ll }
    else {
        my $first := $ll.iterator.pull-one;
        $src.?close;
        $first;
    }
}

method clone {
    RGBAText.new(
        bytes => %_<bytes> // $!bytes.clone,
        width => %_<width> // $!width,
        height => %_<height> // $!height,
        info => %_<info> // $!info,
        scale => %_<default-scale> // $!default-scale,
        comments => %_<comments> // @!comments.clone,
        mappings => %_<mappings> // %!mappings.clone,
        revmap => %_<revmap> // %!revmap.clone);
}

multi method scale { self.scale($!default-scale) }
multi method scale(Int $f where 1) { self.clone }
multi method scale(Int $f where 2..*) {
    my $bytes := buf8.new;
    $bytes.&set-elems($!bytes.elems * $f * $f);

    my int $w = $!width;
    my int $h = $!height;
    my int $fi = $f;
    my uint $elems = $!bytes.elems;

    my int $in = 0;
    loop (my int $y = 0; $y < $h; ++$y) {
        loop (my int $x = 0; $x < $w; ++$x) {
            my uint8 $b0 = $!bytes[$in++];
            my uint8 $b1 = $!bytes[$in++];
            my uint8 $b2 = $!bytes[$in++];
            my uint8 $b3 = $!bytes[$in++];
            loop (my int $dy = 0; $dy < $fi; ++$dy) {
                my int $out = ((($y * $fi + $dy) * $w + $x) * $fi) * 4;
                loop (my int $dx = 0; $dx < $fi; ++$dx) {
# RAKUDOBUG!
#                    $bytes[$out++] = $b0;
#                    $bytes[$out++] = $b1;
#                    $bytes[$out++] = $b2;
#                    $bytes[$out++] = $b3;
                    use nqp;
                    nqp::bindpos_i($bytes, $out++, $b0);
                    nqp::bindpos_i($bytes, $out++, $b1);
                    nqp::bindpos_i($bytes, $out++, $b2);
                    nqp::bindpos_i($bytes, $out++, $b3);
                }
            }
        }
    }

    my &scale-notes = { (.key[0] * $f, .key[1] * $f) => .value }
    self.clone(
        :$bytes, :width($!width * $f), :height($!height * $f),
        :default-scale(1),
        :comments(@!comments.map(&scale-notes)));
}

method encode(Int $bit) {
    my int $i = 0;
    my int $elems = $!bytes.elems;

    join '',
        "=rgba $!width $!height $!info\n",
        $!default-scale > 1 ?? "=scale $!default-scale\n" !! '',
        do gather while $i < $elems {
            take self.PIXEL($bit, $i), $i %% ($!width * 4) ?? "\n" !! ' ';
        }
}

multi method PIXEL(32, int $i is rw) {
    sprintf('%02X', $!bytes[$i++]) xx 4;
}

multi method PIXEL(24, int $i is rw) {
    LEAVE ++$i;
    sprintf('%02X', $!bytes[$i++]) xx 3;
}

multi method PIXEL(16, int $i is rw) {
    ($!bytes[$i++] +> 4).base(16) xx 4;
}

multi method PIXEL(12, int $i is rw) {
    LEAVE ++$i;
    ($!bytes[$i++] +> 4).base(16) xx 3;
}

multi method PIXEL(8, int $i is rw) {
    LEAVE ++$i;
    sprintf('%02X', ($!bytes[$i++] + $!bytes[$i++] + $!bytes[$i++]) div 3);
}

multi method PIXEL(4, int $i is rw) {
    %!revmap{ self.PIXEL(32, $i).join } // '0';
}
