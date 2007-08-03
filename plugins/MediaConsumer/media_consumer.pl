
package MT::Plugin::MediaConsumer;

use strict;
use warnings;

use base qw( MT::Plugin );
use MT;

use MediaConsumer::Item;

use vars qw( $VERSION $plugin );
$VERSION = '0.1';
$plugin = MT::Plugin::MediaConsumer->new ({
    name        => 'MediaConsumer',
    description => 'Media Consumer',
    version     => $VERSION,
    schema_version  => 0.7,

    author_name => 'Apperceptive, LLC',
    author_link => 'http://www.apperceptive.com/',

});
MT->add_plugin ($plugin);

sub instance { $plugin }

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
            
            ### TODO: Fix this after the get_score bug is fixed
            # $row->{"item_score"} = $obj->get_score ('MediaConsumer', $app->user);
            $row->{"item_score"} = 0;
            $row->{"overall_score"} = $obj->score_for ('MediaConsumer') || 0;
            $row->{"ratings"} = $obj->vote_for ('MediaConsumer');
        },
    });
}


1;
