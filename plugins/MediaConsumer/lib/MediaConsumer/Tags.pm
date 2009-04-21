
package MediaConsumer::Tags;

use strict;
use warnings;

sub _hdlr_media_item_author {
    $_[0]->stash ('media_item_author');
}

sub _hdlr_media_item_authors {
    my ($ctx, $args, $cond) = @_;
    my $a = $ctx->stash('asset')
        or return $ctx->_no_asset_error();
    
    my @authors = $a->authors;
    
    my $res = '';
    for my $author (@authors) {
        local $ctx->{__stash}{media_item_author} = $author;
        $res .= $ctx->slurp (@_) or return $ctx->error ($ctx->errstr);
    }
    
    $res;
}

sub _media_item_if_status {
    my ($status, $ctx, $args, $cond) = @_;
    my $a = $ctx->stash('asset')
        or return $ctx->_no_asset_error();

    return $status eq $a->status;
}

sub _hdlr_media_item_if_tobeconsumed {
    _media_item_if_status ('to-be-consumed', @_);
}

sub _hdlr_media_item_if_consuming {
    _media_item_if_status ('consuming', @_);
}

sub _hdlr_media_item_if_consumed {
    _media_item_if_status ('consumed', @_);
}


1;
