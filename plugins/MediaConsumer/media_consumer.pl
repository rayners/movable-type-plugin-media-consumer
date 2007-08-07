
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
    schema_version  => 0.81,

    author_name => 'Apperceptive, LLC',
    author_link => 'http://www.apperceptive.com/',
    
    config_template => 'config.tmpl',
    settings    => MT::PluginSettings->new ([
        [ 'amazon_developer_key', { Default => undef, Scope => 'system' } ],
        [ 'amazon_developer_key', { Default => undef, Scope => 'blog' } ],        
    ]),

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
                        'consume'   => {
                            label   => "Consume",
                            order   => 400,
                            code    => sub {},
                            
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
    
    return $app->build_page ($tmpl, \%param);
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

1;
