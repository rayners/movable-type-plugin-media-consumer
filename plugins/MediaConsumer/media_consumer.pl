
package MT::Plugin::MediaConsumer;

use strict;
use warnings;

use base qw( MT::Plugin );
use MT;

use XML::Simple;
use Data::Dumper;

use MediaConsumer::Item;

use vars qw( $VERSION $plugin );
$VERSION = '0.1';
$plugin = MT::Plugin::MediaConsumer->new ({
    name        => 'MediaConsumer',
    description => 'Media Consumer',
    version     => $VERSION,
    schema_version  => 0.91,

    author_name => 'Apperceptive, LLC',
    author_link => 'http://www.apperceptive.com/',
    
    system_config_template => 'config.tmpl',
    blog_config_template   => 'blog_config.tmpl',
    settings    => MT::PluginSettings->new ([
        [ 'amazon_developer_key', { Default => undef, Scope => 'system' } ],
        [ 'amazon_developer_key', { Default => undef, Scope => 'blog' } ],
        
        [ 'max_rating', { Default => 5, Scope => 'blog' } ],
        [ 'rating_increment', { Default => 0.5, Scope => 'blog' } ],
    ]),
    
    callbacks   => {
        'MT::App::CMS::template_source.edit_entry'  => \&edit_entry_source,
        'MT::App::CMS::template_param.edit_entry'   => \&edit_entry_param,
        'cms_post_save.entry'                       => \&post_save_entry,
        'cms_pre_save.media_consumer_item'          => \&pre_save_media_item,
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
                'MediaItemISBN'     => \&media_item_isbn,
                'MediaItemOverallRating'    => \&media_item_overall_rating,
            },
            block   => {
                'EntryIfMediaReview?'   => \&entry_if_media_review,
                'EntryReviewedItem'     => \&entry_reviewed_item,
                
                'MediaItemIfToBeConsumed?'  => \&media_item_if_to_be_consumed,
                'MediaItemIfConsuming?'     => \&media_item_if_consuming,
                'MediaItemIfConsumed?'      => \&media_item_if_consumed,
                'MediaItemIfReviewed?'      => \&media_item_if_reviewed,
                'MediaItemReviews'          => \&media_item_review, 
                
                'MediaItemIf?'              => \&media_item_if,
            }
        },
        applications => {
            'cms'   => {
                'methods'   => {
                    list_media  => \&list_media,
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
        my $url = qq{http://ecs.amazonaws.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$key&Operation=ItemLookup&ItemId=$asin&Version=2007-05-14&ResponseGroup=Small};
        my $ua = MT->new_ua;
        
        my $res = $ua->get ($url);
        my $xml = $res->content;
        
        my $ref = XMLin ($xml);
        
        my $title = $ref->{Items}->{Item}->{ItemAttributes}->{Title};
        
        my $item = MediaConsumer::Item->new;
        $item->isbn ($asin);
        $item->title ($title);
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
    
    return $app->build_page ($tmpl, \%param);
}

sub start_consuming_items {
    my $app = shift;
    my @id = $app->param ('id');
    
    require MediaConsumer::Item;
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        $item->status (MediaConsumer::Item::CONSUMING);
        $item->save or return $app->trans_error ("Error saving item: [_1]", $item->errstr);
    }
    
    $app->add_return_arg ( 'saved' => 1 );
    $app->call_return;
}

sub finish_consuming_items {
    my $app = shift;
    my @id = $app->param ('id');
    
    require MediaConsumer::Item;
    foreach my $id (@id) {
        next unless $id;
        my $item = MediaConsumer::Item->load ($id) or next;
        $item->status (MediaConsumer::Item::CONSUMED);
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
}


sub media_item_title {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    $item->title;
}

sub media_item_isbn {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ("No media item");
    $item->isbn;
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
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    
    my @e = $item->reviews;
    
    $ctx->stash ('entries', \@e);
    my ($entries_handler) = $ctx->handler_for ('Entries');
    $entries_handler->($ctx, $args);
}

sub media_item_overall_rating {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    $item->score_for ('MediaConsumer') || 0;
}

sub media_item_if {
    my ($ctx, $args) = @_;
    my $item = $ctx->stash ('media_item') or return $ctx->error ('No media item');
    
    if (my $state = $args->{state}) {
        $state = lc ($state);
        require MediaConsumer::Item;
        return $state eq 'to be consumed'   ? $item->status == MediaConsumer::Item::TO_BE_CONSUMED :
               $state eq 'consuming'        ? $item->status == MediaConsumer::Item::CONSUMING :
               $state eq 'consumed'         ? $item->status == MediaConsumer::Item::CONSUMED :
                                              0;
    }
}

1;
