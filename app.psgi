use strict;
use warnings;
use Pod::Simple::XHTML;
use Pod::Simple::Search;
use HTML::Filter::Callbacks;
use Plack::Builder;
use Plack::Request;
use Text::MicroTemplate qw(build_mt);
use URI::Escape qw(uri_escape);
use Pod::Strip;
use File::Slurp qw(slurp);

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

<div id="content">

<dt>
    [ <a href="/src/<?= $module ?>">View Source</a> ]
    [ <a href="/raw/<?= $module ?>">View Raw</a> ]
</dt>

EOH

my $footer = << 'EOF';
</div>
<script type="text/javascript" src="/static/js/prettify.js"></script>
<script type="text/javascript">prettyPrint()</script>
</body>
</html>
EOF

my $filter = HTML::Filter::Callbacks->new;
$filter->add_callbacks(
    pre => +{
        start => sub {
            my ($tag, $c) = @_;
            $tag->add_attr('class', 'prettyprint lang-perl');
        },
    },
);

sub _404() {
    [ 404, ['Content-Type' => 'text/plain'], ["not found"] ];
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
            $content = $filter->process(build_mt($header)->({ module => $module })->as_string.'<pre><code>'.$content.'</code></pre>'.$footer);
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
            $content = $filter->process($content);
            return [ 200, ['Content-Type' => 'text/html', 'Content-Length' => length($content)], [$content] ];
        }
        return _404();
    };
};
