
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
    schema_version  => 0.8,

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
                },
                'menus' => {
                    'manage:media'  => {
                        label   => 'Media',
                        mode    => 'list_media',
                        order   => 300,
                        view    => 'blog',
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


1;
