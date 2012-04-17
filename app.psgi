use strict;
use warnings;
use Pod::Simple::XHTML;
use Pod::Simple::Search;
use Plack::Builder;
use Plack::Request;
use Text::MicroTemplate qw(build_mt);
use URI::Escape qw(uri_escape);
use Pod::Strip;
use File::Slurp qw(slurp);
use HTML::Entities qw(encode_entities);

$|++;

my $header = << 'EOH';
? my $args   = shift;
? my $module = $args->{module};
? my $path   = $args->{path};
<html>
<head>
<title>orepod - <?= $module ?></title>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta http-equiv="Content-Script-Type" content="text/javascript; charset=UTF-8">
<link rel="stylesheet" type="text/css" href='/static/css/style.css'>
<link rel="stylesheet" type="text/css" href='/static/css/prettify.css'>
</head>
<body>

<div id="header">
  <p><?= $module ?></p>
</div>

<div id="navi">
    [ <a href="/<?= $module ?>">Document</a> ]
    [ <a href="/src/<?= $module ?>">Source</a> ]
    [ <a href="/raw/<?= $module ?>">Raw</a> ]
</div>

<div id="content">

EOH

my $footer = << 'EOF';
</div>
<script>
(function () {
    var tags = document.getElementsByTagName("pre");
    for (var i = 0; i < tags.length; i++) {
        tags[i].className = (tags[i].className ? " " : "") + "prettyprint lang-perl";
    }
})();
</script>
<script type="text/javascript" src="/static/js/prettify.js"></script>
<script type="text/javascript">prettyPrint()</script>
</body>
</html>
EOF

sub _404() {
    [ 404, ['Content-Type' => 'text/plain'], ["not found"] ];
}

sub add_line_number {
    my $content = shift;
    my $lines = scalar( () = $content =~ /\n/g );
    my $max = length($lines) + 1;
    my $i = 0;
    $content =~ s{^}{
        $i++;
        sprintf '<a href="#L%i" id="L%i">%*i</a>| ', $i, $i, $max, $i;
    }mge;
    return $content;
}

builder {
    enable 'Static', path => sub { m{^/favicon.ico$} || s{^/static}{} }, root => './static';
    sub {
        my $req = Plack::Request->new(shift);
        my $path = $req->path;
        if ($path eq '/') { return [ 200, ['Content-Type' => 'text/plain'], ['It works!'] ]; }

        my $module;
        if ($path =~ m{^/src}) {
            ($module) = $path =~ m|^/src/(.*)|;
        }
        elsif ($path =~ m{^/raw}) {
            ($module) = $path =~ m|^/raw/(.*)|;
        }
        else {
            ($module) = $path =~ m|^/(.*)|;
        }
        $module =~ s{[/-]}{::}g;

        my $file_path = Pod::Simple::Search->new->find($module) || return _404;
        if ($path =~ m{^/src}) {
            my $p = Pod::Strip->new;
            $p->output_string(\my $content);
            $p->parse_string_document(scalar slurp $file_path);
            $content = build_mt($header)->({ module => $module })->as_string
                .'<pre><code>'
                .add_line_number(encode_entities($content, q|<>"'|))
                .'</code></pre>'
                .$footer
            ;
            return [ 200, ['Content-Type', 'text/html', 'Content-Length' => length($content)], [$content] ];
        }
        elsif ($path =~ m{^/raw}) {
            my $content = slurp $file_path;
            return [ 200, ['Content-Type', 'text/plain', 'Content-Length' => length($content)], [$content] ];
        }

        my $pod = Pod::Simple::XHTML->new;
        $pod->output_string(\my $content);
        $pod->html_header(build_mt($header)->({ module => $module })->as_string);
        $pod->html_footer($footer);
        $pod->perldoc_url_prefix('/');
        $pod->index(1);
        $pod->parse_file($file_path);
        if ($pod->content_seen) {
            return [ 200, ['Content-Type' => 'text/html', 'Content-Length' => length($content)], [$content] ];
        }
        return _404();
    };
};
