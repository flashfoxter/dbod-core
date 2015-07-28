# Copyright (C) 2015, CERN
# This software is distributed under the terms of the GNU General Public
# Licence version 3 (GPL Version 3), copied verbatim in the file "LICENSE".
# In applying this license, CERN does not waive the privileges and immunities
# granted to it by virtue of its status as Intergovernmental Organization
# or submit itself to any jurisdiction.

package DBOD::Api;

use strict;
use warnings;
use Exporter;

use Log::Log4perl qw(:easy);
use REST::Client;
use MIME::Base64;
use JSON;

our ($VERSION, @EXPORT_OK);

$VERSION     = 0.1;
use base qw(Exporter);
@EXPORT_OK   = qw( load_cache get_entity_metadata );

# Loads entity/host entities metadata from cache file
sub load_cache {
    my $config = shift;
    my $filename = $config->{'api'}->{'cachefile'};
    DEBUG 'Loading cache from ' . $filename;
    local $/ = undef;
    open(my $json_fh, "<:encoding(UTF-8)", $filename)
        or return ();
    my $json_text = <$json_fh>;
    close($json_fh);
    my $nested_array = decode_json $json_text;
    my @flat_array = map{@$_} @$nested_array;
    return @flat_array;
}


sub _api_client {
    my ($config, $auth) = @_;
    DEBUG 'Api client connecting to ' . $config->{'api'}->{'host'};
    my $client = REST::Client->new(
        host => $config->{'api'}->{'host'},
        timeout => $config->{'api'}->{'timeout'},
    );
    $client->addHeader('Content-Type', 'application/json');
    $client->addHeader('Accept', 'application/json');
    # Disable SSL host verification
    $client->getUseragent()->ssl_opts( SSL_verify_mode => 0 ); 
    if (defined $auth) {
        my $api_user = $config->{'api'}->{'user'};
        my $api_pass = $config->{'api'}->{'password'};
        DEBUG 'Using basic authentication for user: ' . $api_user;
        $client->addHeader("Authorization", "Basic " . 
            encode_base64("$api_user:$api_pass", "")); 
    }
    return $client; 
}

sub _api_get_entity_metadata {
    my ($entity, $config) = @_;
    my $client = _api_client($config);
    $client->GET(join '/', 
        $config->{'api'}->{'entity_metadata_endpoint'}, $entity);
    my %result;
    $result{'code'} = $client->responseCode();
    if ($result{'code'} eq '200') {
        $result{'response'} = decode_json $client->responseContent();
    } else {
        ERROR 'Failed to contact API server';
        $result{'response'} = ''; 
    }
    return \%result;
}

sub get_entity_metadata {
    my ($entity, $cache, $config) = @_;
    my $result = _api_get_entity_metadata($entity, $config);
    if ($result->{'code'} eq '200') {
        return $result->{'response'};
    } elsif ($result->{'code'} eq '500') {
        WARN 'Returning metadata info from cache';
        return $cache->{$entity} // {};
    } else {
        ERROR 'Metadata not available for entity' . $entity;
        return {};
    }
}

sub set_ip_alias {
    my ($entity, $ipalias, $config) = @_;
    my $client = _api_client($config, 1);
    my $params = $client->buildQuery([ alias => $ipalias ]);
    $client->POST(
        join('/', $config->{'api'}->{'entity_ipalias_endpoint'}, $entity) .
        $params
    );
    my %result;
    $result{'code'} = $client->responseCode();
    if ($result{'code'} eq '201') {
        INFO 'IP Alias succesfully created for ' . $entity;
    } else {
        ERROR 'Resource not available. IP alias creation failed for ' . $entity; 
    }
    return \%result;
}

sub get_ip_alias {
    my ($entity, $config) = @_;
    my $client = _api_client($config);
    $client->GET(join '/', 
        $config->{'api'}->{'entity_ipalias_endpoint'}, $entity);
    my %result;
    $result{'code'} = $client->responseCode();
    if ($result{'code'} eq '200') {
        INFO 'IP Alias fetched for ' . $entity;
        $result{'response'} = decode_json $client->responseContent();
    } else {
        ERROR 'IP alias does not exist for ' . $entity;
        return;
    }
    return \%result;
}

sub remove_ip_alias {
    my ($entity, $config) = @_;
    my $client = _api_client($config, 1);
    $client->DELETE(join '/', 
        $config->{'api'}->{'entity_ipalias_endpoint'}, $entity);
    my %result;
    $result{'code'} = $client->responseCode();
    if ($result{'code'} eq '204') {
        INFO 'IP Alias removed for ' . $entity;
    } else {
        ERROR 'IP alias could not be removed for ' . $entity;
    }
    return \%result;
}

1
;
