
package MediaConsumer::Util;

use strict;
use warnings;

use MT;

use XML::Simple;

sub get_amazon_developer_key {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog) = @_;
    
    my $system_setting = $plugin->get_config_value ('amazon_developer_key', 'system');
    return $system_setting if (!$blog);
    
    my $blog_setting = $plugin->get_config_value ('amazon_developer_key', 'blog:' . $blog->id);
    $blog_setting ? $blog_setting : $system_setting;
}

sub get_amazon_associate_tag {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog) = @_;
    
    my $system_setting = $plugin->get_config_value ('amazon_associate_tag', 'system');
    return $system_setting if (!$blog);
    
    my $blog_setting = $plugin->get_config_value ('amazon_associate_tag', 'blog:' . $blog->id);
    $blog_setting ? $blog_setting : $system_setting;
}

sub get_amazon_data {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog, %params) = @_;

    my $key = $params{key} || get_amazon_developer_key ($blog);
    my $tag = $params{tag} || get_amazon_associate_tag ($blog);
    my $api_version = $params{api_version} || '2008-08-19';
    
    my $url = qq{http://ecs.amazonaws.com/onca/xml?Service=AWSECommerceService&AWSAccessKeyId=$key&AssociateTag=$tag&Version=$api_version};
    
    require MT::Util;
    $url .= '&' . join ('&', map { "$_=" . MT::Util::encode_url ($params{$_}) } keys %params);

    my $ua = MT->new_ua;    
    my $res = $ua->get ($url);
    my $xml = $res->content;
    
    my $ref = XMLin ($xml, ForceArray => ['Author']);
    
    # use Data::Dumper;
    # die Dumper ($ref);
    
    return $ref;
}

sub tags_for_asin {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog, $asin) = @_;
    
    my $cached_tags = MT->request ('amazon_tags') || {};
    if ($cached_tags->{$asin}) {
        return @{$cached_tags->{$asin}};
    }
    else {
        my $ref = get_amazon_data ($blog, Operation => 'ItemLookup', ItemId => $asin, ResponseGroup => 'Tags');
        my @tags = map { $_->{Name} } @{$ref->{Items}->{Item}->{$asin}->{Tags}->{Tag}};
        $cached_tags->{$asin} = [ @tags ];
        MT->request ('amazon_tags', $cached_tags);
        return @tags;
    }
}

sub asset_from_asin {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog, $asin, $params) = @_;
    
    $params ||= {};
    
    my @response_groups = qw( Small Images ItemAttributes Tags EditorialReview );
    my $ref = get_amazon_data ($blog, Operation => 'ItemLookup', ItemId => $asin, ResponseGroup => join (',', @response_groups));

    # use Data::Dumper;
    # die Dumper ($ref);
    my $class = MT->model ("media_item");
    my $title = $ref->{Items}->{Item}->{ItemAttributes}->{Title};
    my $type  = $ref->{Items}->{Item}->{ItemAttributes}->{ProductGroup};
    my $desc  = $ref->{Items}->{Item}->{EditorialReviews}->{EditorialReview}->{Content};
    
    require MT::Util;
    while ($desc =~ s{<div>(.*?)\s*</div>}{$1\n\n}gsmi) { 1 }
    # $desc =~ s{<div>(.*?)\s*</div>}{$1\n\n}gsmi;
    # $desc =~ s{<div>(.*?)\s*</div>}{$1\n\n}gsmi;
    $desc =~ s{\s+\z}{}gsm;
    $desc =~ s{\n{3,}}{\n\n}gsm;
    
    # die Dumper ($desc);
    # $desc =~ s{\s*$}{}smi;
    # $desc =~ s{</div></div></div>}{\n}gi;
    $type = lc ($type);

    # require MediaConsumer::Asset;
    my $item = $class->new;
    $item->blog_id ($blog->id);
    $item->asin ($asin);
    $item->title ($title);
    $item->description ($desc);
    die "Can't" unless ($item->can ('authors'));
    die "Nope" if ($item->has_column ('authors'));
    if ($type eq 'book') {
        my @authors = @{$ref->{Items}->{Item}->{ItemAttributes}->{Author}};
        $item->authors (map { $_ =~ s/\s{2,}/ /g; $_ } @authors);
    }
    
    my $detail_url = $ref->{Items}->{Item}->{DetailPageURL};
    $item->url ($detail_url);

    my @tags = map { $_->{Name} } @{$ref->{Items}->{Item}->{Tags}->{Tag}};

    my $cached_tags = MT->request ('amazon_tags') || {};
    $cached_tags->{$asin} = [ @tags ];
    MT->request ('amazon_tags', $cached_tags);
    
    return $item;
}


sub get_item_details {
    my $plugin = MT->component ('MediaConsumer');
    my ($blog, %params) = @_;
    
    my $asin = $params{asin};
    
    my $ref = get_amazon_data ($blog, Operation => 'ItemLookup', ItemId => $asin, ResponseGroup => "Small,Images,ItemAttributes");
    
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
    $item->blog_id ($blog->id);
            
    $item->save or die "Error saving item:", $item->errstr;
    
    
}


1;
