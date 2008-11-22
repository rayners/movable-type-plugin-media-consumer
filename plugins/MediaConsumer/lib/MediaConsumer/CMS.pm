
package MediaConsumer::CMS;

use strict;
use warnings;

sub create_media_item {
    my $app = shift;
    
    return $app->load_tmpl ('dialog/create_media_item.tmpl');
}

sub verify_media_item {
    my $app = shift;
    my $blog = $app->blog;
    
    my $asin = $app->param ('asin');
    
    require MediaConsumer::Util;
    my $asset = MediaConsumer::Util::asset_from_asin ($blog, $asin);
    
    # use Data::Dumper;
    # die Dumper ($asset);
    my $url = $asset->thumbnail_url (Height => 350);
    # my $url = $asset->thumbnail_url (Height => );
    
    my @tags = MediaConsumer::Util::tags_for_asin ($blog, $asin);
    require MT::Tag;
    my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
    
    my $tags = MT::Tag->join ($tag_delim, @tags);
    
    $app->load_tmpl ('dialog/verify_media_item.tmpl', { 
        asin => $asin,
        title => $asset->title,
        description => $asset->description,
        authors => scalar $asset->authors,
        tags => $tags,
        thumbnail_url => $url,
    });
    
}

sub insert_media_item {
    my $app = shift;
    my $blog = $app->blog;
    
    my $asin = $app->param ('asin');
    
    require MediaConsumer::Util;
    my $asset = MediaConsumer::Util::asset_from_asin ($blog, $asin);
    $asset->status ($app->param ('media_item_status'));
    $asset->description ($app->param ('media_item_description'));
    
    if (my $tags = $app->param ('media_item_tags')) {
        require MT::Tag;
        my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
        my @tags = MT::Tag->split ($tag_delim, $tags);
        $asset->add_tags (@tags);
    }
    
    $asset->save or die $asset->errstr;
    
    return $app->redirect(
        $app->uri(
            'mode' => 'list_assets',
            args   => { 'blog_id' => $app->param('blog_id') }
        )
    );
    
}

# sub param_edit_entry {
#     my ($cb, $app, $param, $tmpl) = @_;
#     
#     my $related_content = $tmpl->getElementsByName('related_content')->[0];
#     my $innerHTML = $related_content->innerHTML;
#     
#     my $new = q{
# <mtapp:widget
#     id="media-consumer-widget"
#     label="<__trans phrase="Media Items">">
# 
#     <mtapp:setting
#         id="reviewed_item_id"
#         shown="1"
#         label="Reviewed Item">
#         <p>Reviewed Item here.</p>
#     </mtapp:setting>
# </mtapp:widget>
#     };
#     
#     # yeah, this sucks, but I can't figure out a way around it yet
#     $innerHTML =~ s{(<div id="category-field")}{$new$1};
#     $related_content->innerHTML ($innerHTML);
# 
#     my @items;
#     if (my $entry_id = $param->{id}) {
#         require MediaConsumer::ItemReview;
#         
#         if (my @reviews = MediaConsumer::ItemReview->load ({ entry_id => $entry_id })) {
#             push @items, $item_review->item_id;
#         }
#     }
# 
#     if (!@items) {
#         push @items, $app->param ('reviewed_item_id') if ($app->param ('reviewed_item_id'));
#     }
# 
#     if (@items) {
#         require MediaConsumer::Item;
#         
#         if (my $item = MediaConsumer::Item->load ($item_id)) {
#             $param->{reviewed_item_id} = $item->id;
#             $param->{reviewed_item_title} = $item->title;
#         }
#     }
# 
# }
# 
# sub param_edit_asset {
#     my ($cb, $app, $param, $tmpl) = @_;
# }


1;
