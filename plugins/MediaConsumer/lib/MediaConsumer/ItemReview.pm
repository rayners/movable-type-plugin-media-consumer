package MediaConsumer::ItemReview;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'item_id'   => 'integer not null',
        'blog_id'   => 'integer not null',
        'entry_id'  => 'integer not null',
    },

    indexes => {
        'id'        => 1,
        'item_id'   => 1,
        'blog_id'   => 1,
    },

    datasource  => 'media_consumer_item_review',
    primary_key => 'id',
});

1;
