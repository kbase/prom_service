use strict;
use warnings;

use Test::More;
use Data::Dumper;

# MAKE SURE WE LOCALLY HAVE JSON RPC LIBS INSTALLED
use_ok("Bio::KBase::PROM::Client");
use_ok("Bio::KBase::workspaceService::Client");
use_ok("Bio::KBase::fbaModelServices::Client");
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
if($create_workspace) {
    my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);
    my $create_workspace_params = {
        workspace => $workspace_name,
        default_permission => 'w',
        auth => $token->token()
    };
    my $workspace_meta = $ws->create_workspace($create_workspace_params);
    print "Workspace Meta Data: \n".Dumper($workspace_meta)."\n";
    exit;
}

my $load_genome = 0;
if($load_genome) {
    my $fba_url = 'http://bio-data-1.mcs.anl.gov/services/fba';
    my $fba = Bio::KBase::fbaModelServices::Client->new($fba_url);
    my $genome_to_workspace_params = {
        genome => "kb|g.372",
        workspace => "workspace_1",
        auth => $token->token(),
        overwrite => 1
    };
    #my $genome_meta = $fba->genome_to_workspace($genome_to_workspace_params);
    #print "Genome Meta Data: \n".Dumper($genome_meta)."\n";
    
    my $genome_to_fba_model_params = {
        genome => 'kb|g.372',
	#genome_workspace => '',
	#probanno_id probanno;
	#workspace_id probanno_workspace;
	#float probannoThreshold;
	#bool probannoOnly;
	#fbamodel_id model;
	workspace => "workspace_1",
        auth =>, $token->token(),
	overwrite=>1,
    };
    my $model_meta = $fba->genome_to_fbamodel($genome_to_fba_model_params);
    print "Genome Meta Data: \n".Dumper($model_meta)."\n";
    
    exit;
}


my $status;
my $prom = Bio::KBase::PROM::Client->new("http://localhost:7060", user_id=>$user_id, password=>$password);
ok(defined($prom),"instantiating PROM client");

################## TEST 1
# test of regulatory network data creation
#my $regulatory_network_id;
#($status, $regulatory_network_id) = $prom->get_regulatory_network_by_genome("kb|g.20848",$workspace_name, $token->token());
#ok($status,"running the method returns something");
#print "STATUS: \n$status\n";
#print "RETURNED ID: $regulatory_network_id\n";
#exit;

################## TEST 2
# test of expression data creation
#my $expression_data_collection_id;
#($status, $expression_data_collection_id) = $prom->get_expression_data_by_genome("kb|g.372",$workspace_name, $token->token());
#ok($status,"running the method returns something");
#print "STATUS: \n$status\n";
#print "RETURNED ID: $expression_data_collection_id\n";
#exit;

################## TEST 3
# test migration of regulatory network namespace
# first we have to generate the mapping using the translation service
#use_ok("Bio::KBase::MOTranslationService::Client");
#my $translation = Bio::KBase::MOTranslationService::Client->new("http://140.221.92.71:7061");
#use DBKernel;
#my $port=3306; my $user='guest'; my $pass='guest';
#my $dbhost='pub.microbesonline.org';
#my $dbKernel = DBKernel->new('mysql','genomics', $user, $pass, $port, $dbhost, '');
#my $moDbh=$dbKernel->{_dbh};
#
#my $tax_id = "211586";
#
#my $query_sequences = [];
#my $sql='SELECT Locus.locusId FROM Locus,Scaffold WHERE Locus.scaffoldId=Scaffold.scaffoldId AND Scaffold.taxonomyId=?';
#my $sth=$moDbh->prepare($sql);
#$sth->execute($tax_id);
#my $locus_ids = [];
#while (my $row=$sth->fetch) {
#    push $locus_ids, ${$row}[0];
#}
#my ($mappingTo20848, $log) = $translation->moLocusIds_to_fid_in_genome_fast($locus_ids,"kb|g.20848");  #MO Version
#my ($mappingTo372, $log2) = $translation->moLocusIds_to_fid_in_genome($locus_ids,"kb|g.372");     #Seed Version
#my $translation_map = {};
#foreach my $map (keys %$mappingTo20848) {
#    if(($mappingTo372->{$map}->{best_match} ne '') && ($mappingTo20848->{$map}->{best_match} ne '')) {
#        $translation_map->{$mappingTo20848->{$map}->{best_match}} = $mappingTo372->{$map}->{best_match};
#    }
#}
#print Dumper($translation_map)."\n";
#
## next we have to actually create the new regulatory network object
#my $new_reg_network_name;
#my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3"; #regulatory network based on g.20848
##my $translation_map = {'kb|g.20848.CDS.3329'=>'gene1','kb|g.20848.CDS.440'=>'gene2' };
#($status, $new_reg_network_name) = $prom->change_regulatory_network_namespace($reg_network_id,$translation_map,$workspace_name, $token->token());
#print "STATUS: \n$status\n";
#print "RETURNED ID: $new_reg_network_name\n";


################## TEST 4
# put it all together and build the actual prom constraints object
my $prom_constraints_id;
#my $expression_data_collection_id = "D459353C-5B85-11E2-89F6-5AEABDAD6664"; # g.372 with 5 experiments
my $expression_data_collection_id = "7F3F4122-5F5E-11E2-862D-B296371F29C2"; # g.372 with ALL (~250) experiments
   ###my $reg_network_id = "CFAC8EDE-59EC-11E2-A47A-6BBB7CBB0AD3"; #original network based on g.20848
my $reg_network_id = "DE633B86-5C34-11E2-A3A3-93838B8565CF"; #new network apped to g.372
my $annot_id = "kb|g.372.fbamdl.1.anno";
($status, $prom_constraints_id) = $prom->create_prom_constraints($expression_data_collection_id,$reg_network_id,$annot_id,$workspace_name, $token->token());
print "STATUS: \n$status\n";
print "RETURNED ID: $prom_constraints_id\n";





done_testing();






