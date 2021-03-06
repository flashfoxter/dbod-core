use strict;
use warnings;

use Test::More;
use File::ShareDir;
use Data::Dumper;

use_ok('DBOD::Network::Api');

use Test::MockObject;
use Test::MockModule;

use JSON;

use DBOD;
use DBOD::Config;


my $share_dir = DBOD::Config::get_share_dir();
my $filename = "$share_dir/test.json";
my %config = ();
my %api = ();
$api{'cachefile'} = "$share_dir/test.json";
$api{'host'} = "https://api-server:443";
$api{'timeout'} = "3";
$api{'user'} = "API-USER";
$api{'password'} = "XXXXXXXXX";
$api{'entity_metadata_endpoint'} = "api/v1/metadata/instance";
$api{'entity_ipalias_endpoint'} = "api/v1/instance/alias";
$api{'entity_endpoint'} = "api/v1/instance";

$config{'api'} = \%api;
$config{'common'} = { template_folder => "${share_dir}/templates" };

# DBOD::Api::load_cache
note( "%config is " . Dumper \%config );
my $cache = DBOD::Network::Api::load_cache($config{'api'}{'cachefile'});
note( Dumper $cache );
isa_ok($cache, 'HASH', 'Cache is a HASH/HASHREF');

# We need to Mock the _api_client method on the
# DBOD::Api module

# We create the class mocking the _api_client return object
my $rest_client = Test::MockObject->new();
$rest_client->set_true('addHeader');
$rest_client->set_true('getUseragent');
$rest_client->set_true('buildQuery');
$rest_client->mock('GET');
$rest_client->mock('PUT');
$rest_client->mock('POST');
$rest_client->mock('DELETE');

my $api = Test::MockModule->new('DBOD::Network::Api');
$api->mock( _api_client => $rest_client );

my $entity = 'success';

# DBOD::Api::get_entity_metadata
subtest 'get_entity_metadata' => sub {

    $rest_client->mock('responseCode', sub { return "200" } );
    $rest_client->mock('responseContent', 
        sub { return "{\"response\":[{\"metadata\":\"test\"}]}" } );
    ok(DBOD::Network::Api::get_entity_metadata('unexistant', $cache, \%config),
        "Method call");
    my $metadata = DBOD::Network::Api::get_entity_metadata('unexistant', $cache,
        \%config);
    isa_ok($metadata, 'HASH', 'Result is a HASH/HASHREF');
    
    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "{\"response\": []}" } );
    $metadata = DBOD::Network::Api::get_entity_metadata('unexistant', $cache, \%config);
    isa_ok($metadata, 'HASH', 'Result is a HASH/HASHREF');
    ok(!exists $metadata->{response}, "Result has empty metadata field");
};

# DBOD::Api::get_ip_alias
subtest 'get_ip_alias' => sub {

    $rest_client->mock('responseCode', sub { return "200" } );
	my %buf = ( ipalias => 'dbod-test.cern.ch', dns_name => 'dns-name-xxx' );
	my %resp = ( response => [\%buf] );
    $rest_client->mock('responseContent', sub { return encode_json \%resp } );
    ok(DBOD::Network::Api::get_ip_alias($entity, \%config), "Method call");
    my $result = DBOD::Network::Api::get_ip_alias($entity, \%config);
    note( Dumper $result );
    ok(exists $result->{dns_name}, 'Result has dns_name field');
    ok(exists $result->{ipalias}, 'Result has ipalias field');

    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "" } );
    is(DBOD::Network::Api::get_ip_alias($entity, \%config), undef, "Method call: error");
};

# DBOD::Api::set_ip_alias 
subtest 'set_ip_alias' => sub {

    $rest_client->mock('responseCode', sub { return "201" } );
    $rest_client->mock('responseContent', sub { return "{\"ipalias\":\"dbod-test\"}" } );
    is(DBOD::Network::Api::set_ip_alias($entity, 'ip-alias',\%config), $OK, "set_ip_alias");
    my $result = DBOD::Network::Api::set_ip_alias($entity, 'ip-alias',\%config);
    note( Dumper $result );

    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "" } );
    is(DBOD::Network::Api::set_ip_alias($entity, 'ip-alias', \%config), $ERROR, "set_ip_alias: error");
    $result = DBOD::Network::Api::set_ip_alias($entity, 'ip-alias', \%config);
    note( Dumper $result );
};

# DBOD::Api::remove_ip_alias
subtest 'remove_ip_alias' => sub {
    
    $rest_client->mock('responseCode', sub { return "204" } );
    $rest_client->mock('responseContent', sub { return "" } );
    is(DBOD::Network::Api::remove_ip_alias($entity, \%config), $OK, "Method call");
    
    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "" } );
    is(DBOD::Network::Api::remove_ip_alias($entity, \%config), $ERROR, "Method call: error");

};

# DBOD::Api::set_metadata 
subtest 'set_metadata' => sub {

    my $metadata = { host => "a", port => "1234" };

    $rest_client->mock('responseCode', sub { return "201" } );
    $rest_client->mock('responseContent', sub { return "{\"ipalias\":\"dbod-test\"}" } );
    ok(DBOD::Network::Api::set_metadata($entity, $metadata, \%config), "Method call");
    my $result = DBOD::Network::Api::set_metadata($entity, \%config);
    note (Dumper $result);
    ok(exists $result->{code}, 'Result has code fieldd');
    ok(!exists $result->{response}, 'Result has not response field');
    
    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "" } );
    ok(DBOD::Network::Api::set_metadata($entity, \%config), "set_metadata: error");
    $result = DBOD::Network::Api::set_metadata($entity, \%config);
    note (Dumper $result);
    ok(exists $result->{code}, 'Result has code fieldd');
    ok(!exists $result->{response}, 'Result has not response field');

};

# DBOD::Api::create_entity 
subtest 'create_entity' => sub {

    my $input = { dbname => "test", subcategory => "MYSQL" };
    print Dumper $input;

    $rest_client->mock('responseCode', sub { return "201" } );
    $rest_client->mock('responseContent', sub { return "" } );
    my $result = DBOD::Network::Api::create_entity($input, \%config);
    is($result, $OK, 'Entity created');
    
    # Test failure
    $rest_client->mock('responseCode', sub { return "404" } );
    $rest_client->mock('responseContent', sub { return "" } );
    $result = DBOD::Network::Api::create_entity($input, \%config);
    is($result, $ERROR, 'Result has code field');

};

done_testing();

