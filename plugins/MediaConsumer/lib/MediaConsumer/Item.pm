package MediaConsumer::Item;

use strict;
use warnings;

use base qw( MT::Object MT::Scorable );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'blog_id'   => 'integer not null',
        'isbn'      => 'string(20)',
        'title'     => 'string(255)',
        'status'    => 'smallint not null',
        'source'   => 'string(255)',
    },

    indexes => {
        'id'    => 1,
    },
    
    defaults    => {
        status  => 1,
    },

    datasource  => 'media_consumer_item',
    primary_key => 'id',
});

use constant TO_BE_CONSUMED => 1;
use constant CONSUMING      => 2;
use constant CONSUMED       => 3;

1;
