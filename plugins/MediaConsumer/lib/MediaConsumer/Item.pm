package MediaConsumer::Item;

use strict;
use warnings;

use MT::Tag; # holds MT::Taggable
use base qw( MT::Object MT::Scorable MT::Taggable );

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
    class_type  => 'media_consumer_item',
});

use constant TO_BE_CONSUMED => 1;
use constant CONSUMING      => 2;
use constant CONSUMED       => 3;

sub class_label {
    MT->translate("Media Item");
}

sub class_label_plural {
    MT->translate("Media Items");
}


1;
