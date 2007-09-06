
package MT::Plugin::MediaConsumer;

use strict;
use warnings;

use base qw( MT::Plugin );
use MT 4;
use MT::Util qw( format_ts );

use XML::Simple;
use Data::Dumper;

use MediaConsumer::Item;

use vars qw( $VERSION $plugin );
$VERSION = '0.1';
$plugin = MT::Plugin::MediaConsumer->new ({
    id          => 'MediaConsumer',
    name        => 'MediaConsumer',
    description => 'Media Consumer',
    version     => $VERSION,
    schema_version  => 0.951,

    author_name => 'Apperceptive, LLC',
    author_link => 'http://www.apperceptive.com/',
    
    system_config_template => 'config.tmpl',
    blog_config_template   => 'blog_config.tmpl',
    settings    => MT::PluginSettings->new ([
        [ 'amazon_developer_key', { Default => undef, Scope => 'system' } ],
        [ 'amazon_developer_key', { Default => undef, Scope => 'blog' } ],
        
        [ 'amazon_associate_tag', { Default => 'mediaconsumer-20', Scope => 'system' } ],
        [ 'amazon_associate_tag', { Default => '', Scope => 'blog' } ],
        
        [ 'max_rating', { Default => 5, Scope => 'blog' } ],
        [ 'rating_increment', { Default => 0.5, Scope => 'blog' } ],
    ]),
    
    callbacks   => {
        'MT::App::CMS::template_source.edit_entry'  => \&edit_entry_source,
        'MT::App::CMS::template_param.edit_entry'   => \&edit_entry_param,
        'cms_post_save.entry'                       => \&post_save_entry,
        'cms_pre_save.media_consumer_item'          => \&pre_save_media_item,
        'cms_post_save.media_consumer_item'         => \&post_save_media_item,
    }

});
MT->add_plugin ($plugin);

sub instance { $plugin }

sub get_amazon_developer_key {
    my $plugin = shift;
    my ($blog) = @_;
    
    my $system_setting = $plugin->get_config_value ('amazon_developer_key', 'system');
    return $system_setting if (!$blog);
    
    my $blog_setting = $plugin->get_config_value ('amazon_developer_key', 'blog:' . $blog->id);
    $blog_setting ? $blog_setting : $system_setting;
}

sub get_amazon_associate_tag {
    my $plugin = shift;
    my ($blog) = @_;
    
    my $system_setting = $plugin->get_config_value ('amazon_associate_tag', 'system');
    return $system_setting if (!$blog);
    
    my $blog_setting = $plugin->get_config_value ('amazon_associate_tag', 'blog:' . $blog->id);
    $blog_setting ? $blog_setting : $system_setting;
}

sub init_registry {
    my $plugin = shift;
    $plugin->{registry} = {
        object_types    => {
            'media_consumer_item'   => 'MediaConsumer::Item',
            'media_consumer_item_review'    => 'MediaConsumer::ItemReview',
        },
        tags    => {
            function    => {
                'MediaItemTitle'    => \&media_item_title,
                'MediaItemArtist'   => \&media_item_artist,
                'MediaItemKey'      => \&media_item_key,
                'MediaItemReleased'    => \&media_item_released,
                'MediaItemRating'   => \&media_item_rating,
                'MediaItemOverallRating'    => \&media_item_overall_rating,
                'MediaItemThumbnailURL'     => \&media_item_thumbnail_url,
                'MediaItemDetailURL'        => \&media_item_detail_url,
                
                'MediaItemImageURL'         => \&media_item_image_url,
            },
            block   => {
                'EntryIfMediaReview?'   => \&entry_if_media_review,
                'EntryReviewedItem'     => \&entry_reviewed_item,
                
                'MediaItemIfToBeConsumed?'  => \&media_item_if_to_be_consumed,
                'MediaItemIfConsuming?'     => \&media_item_if_consuming,
                'MediaItemIfConsumed?'      => \&media_item_if_consumed,
                'MediaItemIfReviewed?'      => \&media_item_if_reviewed,
                'MediaItemReviews'          => \&media_item_reviews, 
                
                'MediaItemIfThumnailURL?'   => \&media_item_thumbnail_url,
                
                'MediaItemIf?'              => \&media_item_if,
                
                'MediaList'                 => \&media_list,
            }
        },
        applications => {
            'cms'   => {
                'methods'   => {
                    list_media  => \&list_media,
                    list_media_consumer_item    => \&list_media,
                    add_media   => \&add_media,
                    view_media  => \&view_media,
                    view_media_consumer_item    => \&view_media,
                },
                'menus' => {
                    'manage:media'  => {
                        label   => 'Media',
                        mode    => 'list_media',
                        order   => 300,
                        view    => 'blog',
                    },
                    'create:media'  => {
                        label   => 'Media Item',
                        dialog    => 'add_media',
                        order   => 300,
                        view    => 'blog',
                    }
                },
                'list_filters'  => {
                    'entry' => {
                        'media_review_entries'  => {
                            label   => 'Media Review Entries',
                            order   => 600,
                            handler => sub {
                                my ($terms, $args) = @_;
                                require MediaConsumer::ItemReview;
                                $args->{join} = MediaConsumer::ItemReview->join_on ('entry_id');
                            },
                        },
                    },
                    'media_consumer_item'   => {
                        'to_be_consumed_items'    => {
                            label   => 'To Be Consumed',
                            order   => 500,
                            handler => sub {
                                my ($terms) = @_;
                                $terms->{status} = 1;
                            }
                        },
                        'consuming' => {
                            label   => 'Consuming',
                            order   => 501,
                            handler => sub {
                                my ($terms) = @_;
                                $terms->{status} = 2;
                            }
                        },
                        'consumed'  => {
                            label   => 'Consumed',
                            order   => 502,
                            handler => sub {
                                my ($terms) = @_;
                                $terms->{status} = 3;
                            }
                        }
                    },
                    'tag'   => {
                        'media_consumer_item'   => {
                            label   => 'Tags with media items',
                            order   => 400,
                        }
                    }
                },
                'list_actions'  => {
                    'media_consumer_item'   => {
                        'start_consuming'   => {
                            label   => "Start Consuming",
                            order   => 400,
                            code    => \&start_consuming_items,
                        },
                        'finish_consuming'  => {
                            label   => "Finish Consuming",
                            order   => 401,
                            code    => \&finish_consuming_items,
                        },
                        'add_tags'  => {
                            label   => 'Add tags',
                            order   => 500,
                            input   => 1,
                            input_label => 'Tags to add to selected media items',
                            code    => \&add_tags_to_media,
                        },
                        'remove_tags'   => {
                            label   => 'Remove tags',
                            order   => 501,
                            input   => 1,
                            input_label => 'Tags to remove to selected media items',
                            code    => \&remove_tags_from_media,
                        },
                        'rate'  => {
                            label   => 'Rate item(s)',
                            order   => 504,
                            input   => 1,
                            input_label => 'Your rating for the selected media items',
                            code    => \&rate_media_items,
                        }
                    }
                }
            }
        }
    };
}

sub list_media {
    my $app = shift;
    
    return $app->listing ({
        type        => 'media_consumer_item',
        template    => $plugin->load_tmpl ('list_media_consumer_item.tmpl'),
        terms       => { blog_id => $app->param ('blog_id') },
        params      => { amazon_developer_key => $plugin->get_amazon_developer_key ($app->blog) },
        code        => sub {
            my ($obj, $row) = @_;
            $row->{"status_" . $obj->status} = 1;
            
            $row->{"item_score"} = $obj->get_score ('MediaConsumer', $app->user);
            $row->{"overall_score"} = $obj->score_for ('MediaConsumer') || 0;
            $row->{"ratings"} = $obj->vote_for ('MediaConsumer');
            $row->{"released_on_formatted"} = format_ts ("%Y-%m-%d", $obj->released_on, $app->blog);
            
            require MT::Tag;
            my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
            $row->{"tags"} = MT::Tag->join ($tag_delim, $obj->tags);
        },
    });
}

sub add_media {
    my $app = shift;
    
    if (my $asin = $app->param ('asin')) {
        my $key = $plugin->get_amazon_developer_key ($app->blog);
        my $tag = $plugin->get_amazon_associate_tag ($app->blog);
        my $url = qq{http://ecs.amazonaws.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$key&AssociateTag=$tag&Operation=ItemLookup&ItemId=$asin&Version=2007-05-14&ResponseGroup=Small,Images,ItemAttributes};
        my $ua = MT->new_ua;
        
        my $res = $ua->get ($url);
        my $xml = $res->content;
        
        my $ref = XMLin ($xml);
        
        my $title = $ref->{Items}->{Item}->{ItemAttributes}->{Title};
        my $type  = $ref->{Items}->{Item}->{ItemAttributes}->{ProductGroup};
        $type = lc ($type);
        
        my $artist = $ref->{Items}->{Item}->{ItemAttributes}->{$type eq 'book' ? 'Author' : 'Artist'};
        my $thumb_url = $ref->{Items}->{Item}->{SmallImage}->{URL};
        my $detail_url = $ref->{Items}->{Item}->{DetailPageURL};
        
        my $pub_date = $ref->{Items}->{Item}->{ItemAttributes}->{$type eq 'book' ? 'PublicationDate' : 'ReleaseDate'};
        $pub_date =~ s/-//g;
        $pub_date .= '000000';
        
        my $item = MediaConsumer::Item->new;
        $item->source ('amazon');
        $item->type (lc ($type));
        $item->artist (ref ($artist) && ref ($artist) eq 'ARRAY' ? join (', ', @$artist) : $artist);
        $item->key ($asin);
        $item->thumb_url ($thumb_url);
        $item->title ($title);
        $item->released_on ($pub_date);
        $item->detail_url ($detail_url);
        $item->blog_id ($app->blog->id);
        
        $item->save or die "Error saving item:", $item->errstr;
        
        return $app->redirect (
            $app->uri (
                'mode'  => 'list_media',
                'args'  => { blog_id => $app->blog->id, added => 1 }
            )
        );
    }
    else {
        my $tmpl = $plugin->load_tmpl ('add_media.tmpl');

        return $app->build_page ($tmpl, {});        
    }
}

sub view_media {
    my $app = shift;
    my $q   = $app->param;
    
    my $tmpl = $plugin->load_tmpl ('edit_media.tmpl');
    my $class = 'MediaConsumer::Item';
    my %param = ();
    
    my $id = $q->param ('id');
    my $obj = $class->load ($id);
    
    my $cols = $class->column_names;
    # Populate the param hash with the object's own values
    for my $col (@$cols) {
        $param{$col} =
          defined $q->param($col) ? $q->param($col) : $obj->$col();
    }
    
    
    if ( $class->can('class_label') ) {
        $param{object_label} = $class->class_label;
    }
    if ( $class->can('class_label_plural') ) {
        $param{object_label_plural} = $class->class_label_plural;
    }
    
    $param{"status_" . $obj->status} = 1;
    
    require MT::Tag;
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    
    $param{"tags"} = MT::Tag->join ($tag_delim, $obj->tags);
    $param{"rating"} = $obj->get_score ('MediaConsumer', $app->user);
    
    return $app->build_page ($tmpl, \%param);
}

sub start_consuming_items {
    my $app = shift;
    my @id = $app->param ('id');
    
    require MediaConsumer::Item;
    require MT::Util;
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        $item->status (MediaConsumer::Item::CONSUMING);
        $item->consume_started (MT::Util::epoch2ts ($app->blog, time));
        $item->consume_finished ('');
        $item->save or return $app->trans_error ("Error saving item: [_1]", $item->errstr);
    }
    
    $app->add_return_arg ( 'saved' => 1 );
    $app->call_return;
}

sub finish_consuming_items {
    my $app = shift;
    my @id = $app->param ('id');
    
    require MediaConsumer::Item;
    require MT::Util;
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        $item->status (MediaConsumer::Item::CONSUMED);
        $item->consume_finished (MT::Util::epoch2ts ($app->blog, time));
        $item->save or return $app->trans_error ("Error saving item: [_1]", $item->errstr);
    }
    
    $app->add_return_arg ( 'saved' => 1 );
    $app->call_return;
}

sub add_tags_to_media {
    my $app = shift;

    my @id = $app->param('id');

    require MT::Tag;
    my $tags      = $app->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MediaConsumer::Item;
    
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        
        $item->add_tags (@tags);
        $item->save or return $app->trans_error ("Error saving item: [_1]", $item->errstr);
    }

    $app->add_return_arg ('saved' => 1);
    $app->call_return;
}

sub remove_tags_from_media {
    my $app = shift;

    my @id = $app->param('id');

    require MT::Tag;
    my $tags      = $app->param('itemset_action_input');
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    my @tags      = MT::Tag->split( $tag_delim, $tags );
    return $app->call_return unless @tags;

    require MediaConsumer::Item;

    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load($id) or next;
        $item->remove_tags(@tags);
        $item->save
          or return $app->trans_error( "Error saving media item: [_1]",
            $item->errstr );
    }

    $app->add_return_arg( 'saved' => 1 );
    $app->call_return;
}

sub rate_media_items {
    my $app = shift;
    
    my @id = $app->param ('id');
    my $rating = $app->param ('itemset_action_input');
    require MediaConsumer::Item;
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        $item->set_score ('MediaConsumer', $app->user, $rating, 1);
        $item->save
            or return $app->trans_error ( "Error saving media item: [_1]",
            $item->errstr);
    }
    
    $app->add_return_arg ( 'saved' => 1 );
    $app->call_return;
}


sub edit_entry_source {
    my ($cb, $app, $tmpl) = @_;
    
    my $old = q{<h3><__trans phrase="Metadata"></h3>};
    
    my $new = q{
<mtapp:setting
    id="reviewed_item_id"
    shown="$reviewed_item_id"
    label="Reviewed Item">
    <mt:var name="reviewed_item_title"><input type="hidden" name="reviewed_item_id" id="reviewed_item_id" value="<mt:var name="reviewed_item_id">" />
</mtapp:setting>
};

    $$tmpl =~ s/\Q$old\E/$old$new/;
}

sub edit_entry_param {
    my ($cb, $app, $param, $tmpl) = @_;
    
    my $item_id;
    
    if (my $entry_id = $param->{id}) {
        require MediaConsumer::ItemReview;
        
        if (my $item_review = MediaConsumer::ItemReview->load ({ entry_id => $entry_id })) {
            $item_id = $item_review->item_id;
        }
    }
    
    $item_id ||= $app->param ('reviewed_item_id');
    if ($item_id) {
        require MediaConsumer::Item;
        
        if (my $item = MediaConsumer::Item->load ($item_id)) {
            $param->{reviewed_item_id} = $item->id;
            $param->{reviewed_item_title} = $item->title;
        }
    }
}

sub post_save_entry {
    my ($cb, $app, $obj) = @_;
    
    if (my $item_id = $app->param ('reviewed_item_id')) {
        require MediaConsumer::ItemReview;
        MediaConsumer::ItemReview->set_by_key ({ item_id => $item_id, blog_id => $obj->blog_id, entry_id => $obj->id }, {});
    }
}

sub pre_save_media_item {
    my ($cb, $app, $obj) = @_;
    # save tags
    my $tags = $app->param('tags');
    if ( defined $tags ) {
        if ( $app->config('NwcReplaceField') =~ m/tags/ig ) {
            $tags = $app->_convert_word_chars( $tags );
        }

        require MT::Tag;
        my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
        my @tags = MT::Tag->split( $tag_delim, $tags );
        $obj->set_tags(@tags);
    }
    
    1;
}

sub post_save_media_item {
    my ($cb, $app, $item) = @_;
    my $rating = $app->param ('rating');
    
    if ($rating) {
        $item->set_score ('MediaConsumer', $app->user, $rating, 1);
        $item->save
            or return $cb->trans_error ( "Error saving media item: [_1]",
            $item->errstr);
    }
    1;
}

sub media_item_title {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    $item->title ? $item->title : "";
}

sub media_item_artist {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    $item->artist ? $item->artist : "";
}

sub media_item_key {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    $item->key ? $item->key : "";
}

sub media_item_released {
    my $item = $_[0]->stash('media_item')
        or return $_[0]->error('No media item');
    my $args = $_[1];
    $args->{ts} = $item->released_on;
    MT::Template::Context::_hdlr_date($_[0], $args);
}

sub media_item_rating {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    
    if (my $entry = $ctx->stash ('entry')) {
        return $item->get_score ('MediaConsumer', $entry->author);
    }
    else {
        my $id = $item->created_by;
        
        require MT::Author;
        my $author = MT::Author->load ($id);
        return $item->get_score ('MediaConsumer', $author);
    }
    
    return 0;
}


sub entry_if_media_review {
    my ($ctx, $args) = @_;
    my $e = $ctx->stash ('entry') or return $ctx->_no_entry_error ($ctx->stash ('tag'));
    
    require MediaConsumer::ItemReview;
    return MediaConsumer::ItemReview->count ({ entry_id => $e->id });
}

sub entry_reviewed_item {
    my ($ctx, $args) = @_;
    my $e = $ctx->stash ('entry') or return $ctx->_no_entry_error ($ctx->stash ('tag'));
    
    require MediaConsumer::ItemReview;
    my $item_review = MediaConsumer::ItemReview->load ({ entry_id => $e->id });
    return "" if (!$item_review);
    
    my $item = $item_review->item;
    return "" if (!$item);
    
    my $builder = $ctx->stash ('builder');
    my $tokens  = $ctx->stash ('tokens');
    
    local $ctx->{__stash}{media_item} = $item;
    
    defined (my $out = $builder->build ($ctx, $tokens))
        or return $ctx->error ($builder->errstr);
    $out;
}

sub media_item_if_to_be_consumed {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    
    require MediaConsumer::Item;
    return $item->status == MediaConsumer::Item::TO_BE_CONSUMED;
}

sub media_item_if_consuming {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    
    require MediaConsumer::Item;
    return $item->status == MediaConsumer::Item::CONSUMING;
}

sub media_item_if_consumed {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    
    require MediaConsumer::Item;
    return $item->status == MediaConsumer::Item::CONSUMED;
}

sub media_item_if_reviewed {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    
    require MediaConsumer::ItemReview;
    return MediaConsumer::ItemReview->count ({ item_id => $item->id });
}

sub media_item_reviews {
    my ($ctx, $args, $cond) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    
    my @e = $item->reviews;
    
    local $ctx->{__stash}{entries} = \@e;
    $ctx->tag ('entries', $args, $cond);
}

sub media_item_overall_rating {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    $item->score_for ('MediaConsumer') || 0;
}

sub media_item_thumbnail_url {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    $item->thumb_url ? $item->thumb_url : "";
}

sub media_item_detail_url {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    $item->detail_url ? $item->detail_url : "";
}


sub media_item_if {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    my @tests;
    require MediaConsumer::Item;
    
    if (my $state = $args->{state}) {
        $state = lc ($state);
        push @tests, sub {
            return $state eq 'to be consumed'   ? $item->status == MediaConsumer::Item::TO_BE_CONSUMED :
                   $state eq 'consuming'        ? $item->status == MediaConsumer::Item::CONSUMING :
                   $state eq 'consumed'         ? $item->status == MediaConsumer::Item::CONSUMED :
                                                  0;
        };
    }
    
    if (my $source = $args->{source}) {
        $source = lc ($source);
        push @tests, sub {
            return $item->source eq $source;
        }
    }
    
    # Defaults to true
    my $res = 1;
    
    $res = $res && $_->() foreach (@tests);
    $res;
}

sub media_list {
    my ($ctx, $args, $cond) = @_;
    
    my (@filters, %blog_terms, %blog_args, %terms, %args);

    $ctx->set_blog_load_context($args, \%blog_terms, \%blog_args)
        or return $ctx->error($ctx->errstr);
    %terms = %blog_terms;
    %args = %blog_args;
    
    my $blog = $ctx->stash ('blog');
    
    my $no_resort = 0;
    my @items;
    
    my $class = MT->model('media_consumer_item');
    
    if ($args->{type}) {
        $terms{type} = lc ($args->{type});
    }
    
    if (my $status = $args->{status}) {
        $status = lc $status;
        $terms{status} = $status eq 'to be consumed' ? MediaConsumer::Item::TO_BE_CONSUMED :
                         $status eq 'consuming'      ? MediaConsumer::Item::CONSUMING :
                                                       MediaConsumer::Item::CONSUMED;
    }
    
    if (my $tag_arg = $args->{tag} || $args->{tags}) {
        require MT::Tag;
        require MT::ObjectTag;

        my $terms;
        if ($tag_arg !~ m/\b(AND|OR|NOT)\b|\(|\)/i) {
            my @tags = MT::Tag->split(',', $tag_arg);
            $terms = { name => \@tags };
            $tag_arg = join " or ", @tags;
        }
        my $tags = [ MT::Tag->load($terms, {
            %args,
            binary => { name => 1 },
            join => MT::ObjectTag->join_on('tag_id', {
                object_datasource => $class->datasource,
                %blog_terms
            }, \%blog_args)
        }) ];
        my $cexpr = $ctx->compile_tag_filter($tag_arg, $tags);
        if ($cexpr) {
            my %map;
            for my $tag (@$tags) {
                my $iter = MT::ObjectTag->load_iter({ 
                    tag_id => $tag->id,
                    object_datasource => $class->datasource,
                    %blog_terms,
                }, { %args, %blog_args });
                while (my $et = $iter->()) {
                    $map{$et->object_id}{$tag->id}++;
                }
            }
            push @filters, sub { $cexpr->($_[0]->id, \%map) };
        } else {
            return $ctx->error(MT->translate("You have an error in your 'tag' attribute: [_1]", $args->{tag} || $args->{tags}));
        }
    }
    if ($args->{sort_by}) {
        if ($class->has_column($args->{sort_by})) {
            $args{sort} = $args->{sort_by};
            $no_resort = 1;
        }
    }
    $args{'sort'} ||= 'created_on';

    if (!@filters) {
        if ((my $last = $args->{lastn}) && (!exists $args->{limit})) {
            $args{direction} = 'descend';
            $args{sort} = 'created_on';
            $args{limit} = $last;
            $no_resort = 0 if $args->{sort_by};
        } else {
            $args{direction} = $args->{sort_order} || 'descend';
            $no_resort = 1 unless $args->{sort_by};
        }
        $args{offset} = $args->{offset} if $args->{offset};
        @items = $class->load(\%terms, \%args);
    } else {
        if (($args->{lastn}) && (!exists $args->{limit})) {
            $args{direction} = 'descend';
            $args{sort} = 'created_on';
            $no_resort = 0 if $args->{sort_by};
        } else {
            $args{direction} = $args->{sort_order} || 'descend';
            $no_resort = 1 unless $args->{sort_by};
        }
        my $iter = $class->load_iter(\%terms, \%args);
        my $i = 0; my $j = 0;
        my $off = $args->{offset} || 0;
        my $n = $args->{lastn};
        ITEM: while (my $mci = $iter->()) {
            for (@filters) {
                next ITEM unless $_->($mci);
            }
            next if $off && $j++ < $off;
            push @items, $mci;
            $i++;
            last if $n && $i >= $n;
        }
    }
    
    my $res = '';
    my $tok = $ctx->stash('tokens');
    my $builder = $ctx->stash('builder');
    unless ($no_resort) {
        my $col = $args->{sort_by} || 'created_on';
        if ('score' eq $col) {
            my $namespace = $args->{namespace};
            my $so = $args->{sort_order} || '';
            my %e = map { $_->id => $_ } @items;
            require MT::ObjectScore;
            my $scores = MT::ObjectScore->sum_group_by(
                { 'object_ds' => $class->datasource, 'namespace' => $namespace },
                { 'sum' => 'score', group => ['object_id'],
                  $so eq 'ascend' ? (direction => 'ascend') : (direction => 'descend'),
                });
            my @tmp;
            while (my ($score, $object_id) = $scores->()) {
                push @tmp, delete $e{ $object_id } if exists $e{ $object_id };
            }
            push @tmp, $_ foreach (values %e);
            @items = @tmp;
        } else {
            my $so = $args->{sort_order} || ($blog ? $blog->sort_order_posts : 'descend') || '';
            if (my $def = $class->column_def($col)) {
                if ($def->{type} =~ m/^integer|float$/) {
                    @items = $so eq 'ascend' ?
                        sort { $a->$col() <=> $b->$col() } @items :
                        sort { $b->$col() <=> $a->$col() } @items;
                } else {
                    @items = $so eq 'ascend' ?
                        sort { $a->$col() cmp $b->$col() } @items :
                        sort { $b->$col() cmp $a->$col() } @items;
                }
            }
        }
    }
    my($last_day, $next_day) = ('00000000') x 2;
    my $i = 0;
    local $ctx->{__stash}{media_consumer_items} = \@items;
    my $glue = $args->{glue};
    my $vars = $ctx->{__stash}{vars} ||= {};
    for my $item (@items) {
        local $vars->{__first__} = !$i;
        local $vars->{__last__} = !defined $items[$i+1];
        local $vars->{__odd__} = ($i % 2) == 0; # 0-based $i
        local $vars->{__even__} = ($i % 2) == 1;
        local $vars->{__counter__} = $i+1;
        local $ctx->{__stash}{blog} = MT::Blog->load ($item->blog_id, {cached_ok => 1});
        local $ctx->{__stash}{blog_id} = $item->blog_id;
        local $ctx->{__stash}{media_item} = $item;
        local $ctx->{current_timestamp} = $item->created_on;
        local $ctx->{modification_timestamp} = $item->modified_on;
        my $this_day = substr $item->created_on, 0, 8;
        my $next_day = $this_day;
        my $footer = 0;
        if (defined $items[$i+1]) {
            $next_day = substr($items[$i+1]->created_on, 0, 8);
            $footer = $this_day ne $next_day;
        } else { $footer++ }
        my $allow_comments ||= 0;
        # $published->{$e->id}++;
        my $out = $builder->build($ctx, $tok, {
            %$cond,
            # DateHeader => ($this_day ne $last_day),
            # DateFooter => $footer,
            # EntriesHeader => $class_type eq 'entry' ?
            #     (!$i) : (),
            # EntriesFooter => $class_type eq 'entry' ?
            #     (!defined $entries[$i+1]) : (),
            # PagesHeader => $class_type ne 'entry' ?
            #     (!$i) : (),
            # PagesFooter => $class_type ne 'entry' ?
            #     (!defined $entries[$i+1]) : (),
        });
        return $ctx->error( $builder->errstr ) unless defined $out;
        $last_day = $this_day;
        $res .= $glue if defined $glue && $i;
        $res .= $out;
        $i++;
    }
    if (!@items) {
        return MT::Template::Context::_hdlr_pass_tokens_else(@_);
    }

    $res;
    
    
}


1;
