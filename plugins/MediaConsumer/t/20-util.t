
use lib qw( t/lib lib extlib );

use strict;
use warnings;

use MT::Test qw( :db :data );
use Test::More qw(no_plan);
use Test::Deep;

require_ok ('MediaConsumer::Util');

require MT;
my $p = MT->component ('mediaconsumer');
$p->set_config_value ('amazon_developer_key', '12ESEPSDEWXXWKVPFM82');

require MT::Blog;
my $blog = MT::Blog->load (1);
my $a = MediaConsumer::Util::asset_from_asin ($blog, '0765356368');

is ($a->title, 'Mainspring', "Got the right title");
cmp_bag ([ $a->authors ], ['Jay Lake'], "Got the right author");
is ($a->publisher, 'Tor Science Fiction', "Got the right publisher");

