
package MediaConsumer::Asset;

use strict;
use warnings;

use List::Util qw( first );

use base qw( MT::Asset );

__PACKAGE__->install_properties( {
    class_type => 'media_item',
    column_defs => {
        'consume_started'   => 'datetime meta indexed',
        'consume_finished'  => 'datetime meta indexed',
        'source'            => 'string meta',
    },
} );

sub class_label {
    MT->translate ('Media Item');
}

sub class_label_plural {
    MT->translate ('Media Items');
}

sub asin {
    shift->file_name (@_);
}

sub title {
    shift->label (@_);
}

sub authors {
    my $asset = shift;
    my @tags = $asset->tags;
    my @author_tags = grep { /^\@mc:author:/ } @tags;
    if (my @new_authors = @_) {
        $asset->remove_tags (@author_tags) if (@author_tags);
        $asset->add_tags ( map { '@mc:author:' . $_ } @new_authors);
        return wantarray ? @new_authors : join (', ', @new_authors);
    }
    else {        
        my @authors = map { $_ =~ s/^\@mc:author://; $_ } @author_tags;
        return wantarray ? @authors : join (', ', @authors);
    }
}

sub artists {
    my $asset = shift;
    my @tags = $asset->tags;
    my @author_tags = grep { /^\@mc:artist:/ } @tags;
    if (my @new_authors = @_) {
        $asset->remove_tags (@author_tags) if (@author_tags);
        $asset->add_tags ( map { '@mc:artist:' . $_ } @new_authors);
        return wantarray ? @new_authors : join (', ', @new_authors);
    }
    else {        
        my @authors = map { $_ =~ s/^\@mc:artist://; $_ } @author_tags;
        return wantarray ? @authors : join (', ', @authors);
    }
}


# the status value is actually stored in a @status:<str> private tag
# to make it easier to access in the various spots in MT
sub status {
    my $asset = shift;
    my @tags = $asset->tags;
    my $status_tag = first { /^\@mc:status:/ } @tags;
    if (my $status = shift) {
        $asset->remove_tags ($status_tag) if ($status_tag);
        $asset->add_tags ('@mc:status:' . $status);
        return $status;
    }
    else {
        return if (!$status_tag);
        $status_tag =~ s/^\@mc:status://;
        return $status_tag;        
    }
}

my %amazon_size_str = (
    small   => 'SCTZZZZZZZ',
    medium  => 'SCMZZZZZZZ',
    large   => 'SCLZZZZZZZ',
);

sub thumbnail_url {
#     # die "In thumbnail_url";
    my $item = shift;
    my (%params) = @_;
    my $base_url = 'http://images.amazon.com/images/P/';
    $base_url .= $item->asin;
    $base_url .= '.01.';
    
    my $size = $params{size} || 'large';
    # my $size = 'small';
    my @options = ();
#     
#     # if (my $ds = $args->{drop_shadow}) {
#     #     push @options, ( lc ($ds) eq 'right' ? 'PC' : 'PB' );
#     # }
#     # 
    push @options, $amazon_size_str{$size};
    # push @options, 'SCLZZZZZZZ';
    if ($params{'Height'} && $params{'Width'}) {
        push @options, 'AA' . ( $params{'Height'} > $params{'Width'} ? $params{'Width'} : $params{'Height'});        
    }
    elsif ($params{'Width'}) {
        push @options, 'SX' . $params{'Width'};
    }
    elsif ($params{'Height'}) {
        push @options, 'SY' . $params{'Height'};
    }
    
    $base_url .= join ('_', '', @options, '') . '.jpg';
    
    return $base_url;    
}

sub as_html {
    my $asset = shift;
    my ($params) = @_;
    
    my $text = sprintf '<a href="%s"><img src="%s" title="%s"/></a>',
        MT::Util::encode_html($asset->url),
        MT::Util::encode_html($asset->thumbnail_url),
        MT::Util::encode_html($asset->title);
    return $asset->enclose ($text);
}


sub has_thumbnail {
    1;
}

sub edit_template_param {
    my $asset = shift;
    my ($cb, $app, $param, $tmpl) = @_;
    
    my $tags = $param->{tags};
    require MT::Tag;
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags = MT::Tag->split( $tag_delim, $tags );
    @tags = grep { $_ !~ /^\@mc:/ } @tags;
    $param->{tags} = MT::Tag->join ( $tag_delim, @tags );
    
}

# sub media_item_image_url {
#     my ($ctx, $args) = @_;
#     
#     my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
#     
#     if ($item->source eq 'amazon') {
#         my $base_url = 'http://images.amazon.com/images/P/';
#         $base_url .= $item->key;
#         $base_url .= '.01.';
#         
#         my $size = $args->{size} || 'medium';
#         my @options = ();
#         
#         if (my $ds = $args->{drop_shadow}) {
#             push @options, ( lc ($ds) eq 'right' ? 'PC' : 'PB' );
#         }
#         
#         push @options, $amazon_size_str{$size};
#         
#         $base_url .= join ('_', '', @options, '') . '.jpg';
#         
#         return $base_url;
#     }
#     
#     return "";
# }


1;
