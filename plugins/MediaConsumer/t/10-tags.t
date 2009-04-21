
use lib qw( t/lib lib extlib );

use strict;
use warnings;

use MT::Test qw( :db :data );
use Test::More qw(no_plan);

require_ok('MediaConsumer::Util');

require MT;
my $p = MT->component('mediaconsumer');
$p->set_config_value( 'amazon_developer_key', '12ESEPSDEWXXWKVPFM82' );

require MT::Blog;
my $blog = MT::Blog->load(1);
my $a = MediaConsumer::Util::asset_from_asin( $blog, '0316068063' );
$a->status('consumed');

tmpl_out_like(
    '<mt:assetlabel>', {},
    { blog => $blog, blog_id => 1, asset => $a },
    qr/^\QWinterbirth (Godless World)\E$/,
    "mt:assetlabel produces the title"
);

tmpl_out_like(
    '!!<mt:mediaitemauthors>[[ <mt:mediaitemauthor> ]]</mt:mediaitemauthors>!!',
    {},
    { blog => $blog, blog_id => 1, asset => $a },
    qr/^\Q!![[ Brian Ruckley ]]!!\E$/,
    "mt:mediaitemauthors + mt:mediaitemauthor produces the author"
);

my @statuses = ( 'to-be-consumed', 'consuming', 'consumed' );
for my $status (@statuses) {
    my $tag = $status;
    $tag =~ s/-//g;
    tmpl_out_like(
        "<mt:mediaitemif$tag>True!<mt:else>False!</mt:mediaitemif$tag>",
        {},
        { blog => $blog, blog_id => 1, asset => $a },
        qr/^False!$/,
        "mt:mediaiitemif$tag is false"
    );

    $a->status($status);
    tmpl_out_like(
        "<mt:mediaitemif$tag>True!<mt:else>False!</mt:mediaitemif$tag>",
        {},
        { blog => $blog, blog_id => 1, asset => $a },
        qr/^True!$/,
        "mt:mediaiitemif$tag is true"
    );

}

my @props =
  ( [ 'publisher', 'Orbit' ], [ 'source', 'amazon' ],
    [ 'status', 'consumed' ] );

for my $prop (@props) {
    my ( $k, $v ) = @$prop;
    tmpl_out_like(
        "<mt:assetproperty property='$k'>",
        {}, { blog => $blog, blog_id => 1, asset => $a },
        qr/^$v$/, "mt:assetproperty with $k produces '$v'"
    );

}
