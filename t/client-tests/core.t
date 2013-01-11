use strict;
use warnings;

use Test::More tests => 5;
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


# AUTH INFORMATION FOR TESTING
my $user_id='kbasepromuser1';
my $password='open4me!';
my $workspace_name="workspace_1";
my $token = Bio::KBase::AuthToken->new(user_id => $user_id, password => $password);

#create a workspace if it doesn't exist already (set flag to 1 to create workspace)
my $create_workspace = 0;
my $workspace_url = 'http://bio-data-1.mcs.anl.gov/services/fba_gapfill';
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


my $status;
my $prom = Bio::KBase::PROM::Client->new("http://localhost:7060", user_id=>$user_id, password=>$password);
ok(defined($prom),"instantiating PROM client");

# test of regulatory network data creation
#my $regulatory_network_id;
#($status, $regulatory_network_id) = $prom->get_regulatory_network_by_genome("kb|g.20848",$workspace_name, $token->token());
#ok($status,"running the method returns something");
#print "STATUS: \n$status\n";
#print "RETURNED ID: $regulatory_network_id\n";
#exit;

# test of expression data creation
#my $expression_data_collection_id;
#($status, $expression_data_collection_id) = $prom->get_expression_data_by_genome("kb|g.372",$workspace_name, $token->token());
#ok($status,"running the method returns something");
#print "STATUS: \n$status\n";
#print "RETURNED ID: $expression_data_collection_id\n";
#exit;


# test migration of regulatory network namespace
my $new_reg_network_name;
my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3";
#kb|g.20848.CDS.3329	kb|g.20848.CDS.440
my $map = {'kb|g.20848.CDS.3329'=>'gene1','kb|g.20848.CDS.440'=>'gene2' };
($status, $new_reg_network_name) = $prom->change_regulatory_network_namespace($reg_network_id,$map,$workspace_name, $token->token());
print "STATUS: \n$status\n";
print "RETURNED ID: $new_reg_network_name\n";
exit;


# put it all together
my $prom_constraints_id;
my $expression_data_collection_id = "D459353C-5B85-11E2-89F6-5AEABDAD6664";
my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3";
($status, $prom_constraints_id) = $prom->create_prom_constraints($expression_data_collection_id,$reg_network_id,$workspace_name, $token->token());

print "STATUS: \n$status\n";
print "RETURNED ID: $prom_constraints_id\n";

exit;







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






