use strict;
use warnings;

use Test::More tests => 4;
use Data::Dumper;
use Test::More;

# MAKE SURE WE LOCALLY HAVE JSON RPC LIBS INSTALLED
use_ok("Bio::KBase::PROM::Client");
use_ok("Bio::KBase::workspaceService::Client");
use_ok("Bio::KBase::AuthToken");

# MAKE A CONNECTION (DETERMINE THE URL TO USE BASED ON THE CONFIG MODULE)
#my $host=getHost(); my $port=getPort();
#print "-> attempting to connect to:'".$host.":".$port."'\n";
#


# AUTH INFORMATION
my $user_id='kbasepromuser1';
my $password='open4me!';
my $workspace_name="workspace_1";
my $token = Bio::KBase::AuthToken->new(user_id => $user_id, password => $password);

#create a workspace if it doesn't exist already (set flag to 1 to create workspace)
my $create_workspace = 0;
my $workspace_url = 'http://140.221.92.231/services/workspaceService/';
if($create_workspace==1) {
    my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);
    my $create_workspace_params = {
        workspace => $workspace_name,
        default_permission => 'w',
        auth => $token->token()
    };
    my $workspace_meta = $ws->create_workspace($create_workspace_params);
    print 'Workspace Meta Data: \n'.Dumper($workspace_meta)."\n";
    exit;
}


my $prom = Bio::KBase::PROM::Client->new("http://localhost:7060", user_id=>$user_id, password=>$password);
ok(defined($prom),"instantiating PROM client");

my ($status, $expression_data_collection_id) = $prom->retrieve_expression_data("kb|g.0",$workspace_name, $token->token());

ok($status,"running the method returns something");

print "STATUS: \n$status\n";
print "RETURNED ID: $expression_data_collection_id\n";


die 1;










# creating a new regulatory model with regprecise

use Bio::KBase::Regulation::Client;

my $reg = Bio::KBase::Regulation::Client->new('http://140.221.92.147:8080/KBaseRegPreciseRPC/regprecise');
#my $reg = Bio::KBase::Regulation::Client->new('http://140.221.92.231/services/regprecise/');
# get a list of model collections
my $collections = $reg->getRegulomeModelCollections();
print Dumper($collections)."\n";

# we can see that we have a collection for Shewenella, for instance, with ID=1:
#        {
#            'buildParams' => '',
#            'createDate' => undef,
#            'regulomeSource' => 'REGPRECISE_CURATED',
#            'taxonName' => 'Shewanella',
#            'name' => 'Shewanella',
#           'collectionId' => '1',
#            'phylum' => 'Proteobacteria/gamma',
#            'description' => undef,
#            'regulomeModelCount' => 16
#          }

# let's get the models in the collection just to be sure.
my $regulomeModels = $reg->getRegulomeModelsByCollectionId("1");
print Dumper($regulomeModels)."\n"; 

# but we want a model for "kb|g.372"!  let's build it (commented out because we only need to build it once)
#my $param = {
#    targetGenomeId => "kb|g.372",
#    sourceRegulomeCollectionId => "1"
#};
#my $processState = $reg->buildRegulomeModel($param);
#print Dumper($processState)."\n";

# we can look up our process ID to see how much longer to wait
my $processState = $reg->getProcessState("259");
print Dumper($processState)."\n";


# once it is complete, we can retrieve our model

#"kb|g.9677.regulome.0"


my $regulonModels = $reg->getRegulonModel("kb|g.20905.regulome.0");
print Dumper($regulonModels)."\n";






