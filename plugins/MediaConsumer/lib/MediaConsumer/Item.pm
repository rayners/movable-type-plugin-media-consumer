package MediaConsumer::Item;

use strict;
use warnings;

use MT::Tag; # holds MT::Taggable
use base qw( MT::Object MT::Scorable MT::Taggable );

__PACKAGE__->install_properties ({
    column_defs => {
        'id'        => 'integer not null primary key auto_increment',
        'blog_id'   => 'integer not null',
        'key'       => 'string(20)',
        'author'    => 'string(255)',
        'title'     => 'string(255)',
        'status'    => 'smallint not null',
        'source'    => 'string(255)',
        'type'      => 'string(20)',
        'thumb_url' => 'string(255)',
        'consume_started'   => 'datetime',
        'consume_finished'  => 'datetime',
        
        'published_on'      => 'datetime',
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
    audit => 1,
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

sub reviews {
    my $obj = shift;
    
    require MediaConsumer::ItemReview;
    return (MediaConsumer::ItemReview->load ({ item_id => $obj->id }));
}


1;
