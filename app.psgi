use strict;
use warnings;
use lib::xi;
use Pod::Simple::XHTML;
use Pod::Simple::Search;
use HTML::Filter::Callbacks;
use Plack::Builder;
use Text::MicroTemplate qw(build_mt);

my $header = << 'EOH';
? my $args   = shift;
? my $module = $args->{module};
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

builder {
    enable 'Static', path => sub { m{^/favicon.ico$} || s{^/static}{} }, root => './static';
    sub {
        my $env = shift;
        my $path = $env->{PATH_INFO};
        if ( $path eq '/' ) { return [ 200, ['Content-Type' => 'text/plain'], ['It works!'] ]; }

        $path =~ s{^/}{};
        (my $mod = $path) =~ s{[/-]}{::}g;

        if (my $file_path = Pod::Simple::Search->new->find($mod)) {
            my $pod = Pod::Simple::XHTML->new;
            $pod->output_string(\my $content);
            $pod->html_header(build_mt($header)->(+{ module => $mod })->as_string);
            $pod->html_footer($footer);
            $pod->perldoc_url_prefix('/');
            $pod->index(1);
            $pod->parse_file($file_path);
            if ($pod->content_seen) {
                $content = $filter->process($content);
                return [ 200, ['Content-Type' => 'text/html', 'Content-Length' => length($content)], [$content] ];
            }
        }
        [ 404, ['Content-Type' => 'text/plain'], ["not found $mod"] ];
    };
};
