unit class Image::RGBA::Text;

my constant RGBA = Image::RGBA::Text;

has Buf  $.bytes;
has uint $.width;
has uint $.height;
has Str  $.info;

has @.annotations;
has @.comments;
has %.mappings;

sub set-elems(\obj, \elems) {
    use nqp;
    nqp::setelems(obj, elems);
}

method parse(RGBA:U: $src) {
    my ($img, $bytes);
    my $N = -1;
    my $n = 0;

    my grammar Line {
        token TOP {
            [   <.header>
            |   <.map>
            |   <.note>
            |   <.pixels>? \h* <.comment>?
            ]
        }

        token header {
            '=rgba' \h+ (\d+) \h+ (\d+) [ \h+ (.*) ]?
        }

        token note {
            '=note' <?{ defined $img }> \h+ (\d+) \h+ (\d+) [ \h+ (.*) ]?
        }

        token map {
            '=map' <?{ defined $img }> [ \h+ (\H+) \h+ (<.xdigit>+) ]+
        }

        token comment {
            '#' <?{ defined $img }> \h* (.*)
        }

        token pixels {
            <?{ defined $img }> [ \h+ (<-[\h#]>+) ]+
        }
    }

    my $actions = class {
        method header($/) {
            my $width = +$0;
            my $height = +$1;
            my $info = $2 ?? ~$2 !! '';

            $bytes := Buf.new;
            $N = $width * $height * 4;

            $bytes.&set-elems($N);
            $img = RGBA.new(:$width, :$height, :$info, :$bytes);
        }

        method map($/) {
            $img.mappings{~<<$0} = ~<<$1;
        }

        method note($/) {
            $img.annotations.push((+$0.Str, +$1.Str) => $2.?Str);
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
                        $bytes[$n++] = :16($_) // return $img = Nil
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

                    default { !!! }
                }
            }
        }
    }

    gather for $src.lines {
        Line.parse($_, :$actions);
        if $n == $N {
            take $img;
            $img = Nil;
            $N = -1;
            $n = 0;
        }
    }
}

method strip(Bool :$info, Bool :$annotations, Bool :$comments, Bool :$mappings) {
    $!info = Nil unless $info === False;
    @!annotations = () unless $annotations === False;
    @!comments = () unless $comments === False;
    %!mappings = () unless $mappings === False;
    self;
}

method clone {
    RGBA.new:
        bytes => %_<bytes> // $!bytes.clone,
        width => %_<width> // $!width,
        height => %_<height> // $!height,
        info => %_<info> // $!info,
        annotations => %_<annotations> // @!annotations.clone,
        comments => %_<comments> // @!comments.clone,
        mappings => %_<mappings> // %!mappings.clone;
}

multi method scale(Int $f where 1) { self.clone }

multi method scale(Int $f where 2..*) {
    my $bytes := Buf.new;
    $bytes.&set-elems($!bytes.elems * $f * $f);

    my int $w = $!width;
    my int $h = $!height;
    my int $fi = $f;

    loop (my int $y = 0; $y < $h; ++$y) {
        loop (my int $x = 0; $x < $w; ++$x) {
            loop (my int $dy = 0; $dy < $fi; ++$dy) {
                my int $yy = $y * $fi + $dy;
                loop (my int $dx = 0; $dx < $fi; ++$dx) {
                    my int $in = ($y * $w + $x) * 4;
                    my int $out = (($yy * $w + $x) * $fi + $dx) * 4;
                    $bytes[$out++] = $!bytes[$in++];
                    $bytes[$out++] = $!bytes[$in++];
                    $bytes[$out++] = $!bytes[$in++];
                    $bytes[$out++] = $!bytes[$in++];
                }
            }
        }
    }

    my &scale-notes = { (.key[0] * $f, .key[1] * $f) => .value }
    self.clone:
        :$bytes :width($!width * $f), :height($!height * $f),
        :annotations(@!annotations.map(&scale-notes)),
        :comments(@!comments.map(&scale-notes));
}

method dump($file = '-', Bool :$w, Bool :$a) {
    my $fh = open $file, |($a ?? :a !! $w ?? :w !! :x) or die;
    self.DUMP($fh, |%_);

    # do not close stdout!
    $fh.close
        unless $fh.path ~~ IO::Special;

    self;
}

multi method DUMP($fh, Bool :$raw!) {
    $fh.write($!bytes);
}

multi method DUMP($fh, Bool :$meta!) {
    $fh.print:
        qq:to/__END__/,
            [meta]
            width  = $!width
            height = $!height
            info   = $!info
            __END__

        @!annotations ?? qq:to/__END__/ !! '',

            [annotations]
            {
                join "\n", @!annotations.map:
                    { "{ .key[0] },{ .key[1] },{ .value } " };
            }
            __END__

        @!comments ?? qq:to/__END__/ !! '';

            [comments]
            {
                join "\n", @!comments.map:
                    { "{ .key[0] },{ .key[1] },{ .value } " };
            }
            __END__
}

multi method DUMP($fh, Int :$bit = 32) {
    $fh.print: "=rgba $!width $!height $!info\n";
    $fh.print: "=note { .key[0] } { .key[1] } { .value }\n" for @!annotations;
    self.DUMP($fh, $bit);
}

multi method DUMP($fh, 32) {
    my uint $i = 0;
    while $i < $!bytes.elems {
        $fh.print: ' ', sprintf('%02X', $!bytes[$i++]) xx 4;
        $fh.print("\n") if $i %% ($!width * 4);
    }
}

multi method DUMP($fh, 24) {
    my uint $i = 0;
    while $i < $!bytes.elems {
        $fh.print: ' ', sprintf('%02X', $!bytes[$i++]) xx 3;
        ++$i; # skip alpha
        $fh.print("\n") if $i %% ($!width * 4);
    }
}

multi method DUMP($fh, 16) {
    my uint $i = 0;
    while $i < $!bytes.elems {
        $fh.print: ' ', ($!bytes[$i++] +> 4).base(16) xx 4;
        $fh.print("\n") if $i %% ($!width * 4);
    }
}

multi method DUMP($fh, 12) {
    my uint $i = 0;
    while $i < $!bytes.elems {
        $fh.print: ' ', ($!bytes[$i++] +> 4).base(16) xx 3;
        ++$i; # skip alpha
        $fh.print("\n") if $i %% ($!width * 4);
    }
}

multi method DUMP($fh, 8) {
    my uint $i = 0;
    while $i < $!bytes.elems {
        my $value = ($!bytes[$i++] + $!bytes[$i++] + $!bytes[$i++]) div 3;
        $fh.print: ' ', sprintf('%02X', $value);
        ++$i; # skip alpha
        $fh.print("\n") if $i %% ($!width * 4);
    }
}


multi method DUMP($fh, 4) { ... }

my $bit = 32;
sub dump-argfiles($bit) { .dump(:$bit) for RGBA.parse($*ARGFILES) }
sub image-rgba-text-dump32 is export { dump-argfiles 32 }
sub image-rgba-text-dump24 is export { dump-argfiles 24 }
sub image-rgba-text-dump16 is export { dump-argfiles 16 }
sub image-rgba-text-dump12 is export { dump-argfiles 12 }
sub image-rgba-text-dump8  is export { dump-argfiles  8 }
sub image-rgba-text-dump4  is export { dump-argfiles  4 }
