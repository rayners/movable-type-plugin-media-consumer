
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
    
    if (my $ds = $params{drop_shadow}) {
        push @options, ( lc ($ds) eq 'right' ? 'PC' : 'PB' );
    }
    
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
    
    if ($params->{insert_type} eq 'image') {
        my $wrap_style = '';
        if ($params->{align}) {
            $wrap_style = 'class="mt-image-' . $params->{align} . '" ';
            if ( $params->{align} eq 'none' ) {
                $wrap_style .= q{style=""};
            }
            elsif ( $params->{align} eq 'left' ) {
                $wrap_style .= q{style="float: left; margin: 0 20px 20px 0;"};
            }
            elsif ( $params->{align} eq 'right' ) {
                $wrap_style .= q{style="float: right; margin: 0 0 20px 20px;"};
            }
            elsif ( $params->{align} eq 'center' ) {
                $wrap_style .= q{style="text-align: center; display: block; margin: 0 auto 20px;"};
            }
            
        }
        my $text = sprintf '<a href="%s"><img src="%s" title="%s" %s /></a>',
            MT::Util::encode_html($asset->url),
            MT::Util::encode_html($asset->thumbnail_url (%$params)),
            MT::Util::encode_html($asset->title),
            $wrap_style;
        return $asset->enclose ($text);        
    }
    else {
        my $text = sprintf '<a href="%s">%s</a>',
            MT::Util::encode_html ($asset->url),
            MT::Util::encode_html ($params->{link_text_sel} ? $params->{link_text_sel} : $params->{link_text_text});
        return $asset->enclose ($text);
    }
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

    my $desc_field = $tmpl->getElementById ('description');
    my $html = $desc_field->innerHTML;
    $html =~ s/short/medium/;
    $desc_field->innerHTML ($html);
    
    my $status_field = $tmpl->createElement ('app:setting', { id => 'mc_status', label => 'Status', label_class => "text-top" });
    my $status_html = q{<select name='mc_status' id='mc_status'>
    <option value="to-be-consumed"<mt:if var='mc_status' eq='to-be-consumed'> selected="selected"</mt:if>>To be consumed</option>
    <option value="consuming"<mt:if var='mc_status' eq='consuming'> selected="selected"</mt:if>>Consuming</option>
    <option value="consumed"<mt:if var='mc_status' eq='consumed'> selected="selected"</mt:if>>Consumed</option>
    </select>};
    $status_field->innerHTML ($status_html);    
    $tmpl->insertBefore ($status_field, $tmpl->getElementById ('label'));
    $param->{mc_status} = $asset->status;
    
}

sub insert_options {
    my $asset = shift;
    my ($param) = @_;

    my $app   = MT->instance;
    my $perms = $app->{perms};
    my $blog  = $asset->blog or return;
    my $plugin = MT->component ('MediaConsumer');
    
    my @link_text_loop;
    push @link_text_loop, map {{ link_text_value => $_, link_text_text => $_ }} ($asset->title, $asset->title . ' by ' . join (', ', $asset->authors));
    $param->{link_text_loop} = \@link_text_loop;

    my $tmpl = $plugin->load_tmpl ('dialog/insert_options.tmpl', $param) or MT->log ($plugin->errstr);
    my $html = $app->build_page($tmpl, $param );
    if (!$html) {
        MT->log ($app->errstr);
    }
    return $html;
    
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
