#
# NOTE THAT THIS ASSUMES THAT YOU INVOKED THE CODE VIA MAKE TEST, OTHERWISE PATHS WILL BE WRONG.
#
# This test performs a test of the expression data creation and upload methods of the prom service,
# which should all be moved to the expression service at some point.  Note that this does not test
# the method to pull expression data from the CDS
#

#exit; # how else can I control what tests to run from the 'make test' target ?!?!?!?
print "-----------------------------------------------------\n";
print "running tests in expression-data-load.t\n";

use strict;
use warnings;

use Test::More;
use Data::UUID;
use Data::Dumper;

# MAKE SURE WE LOCALLY HAVE JSON RPC LIBS INSTALLED
use_ok("Bio::KBase::PROM::Client");
use_ok("Bio::KBase::workspaceService::Client");
use_ok("Bio::KBase::AuthToken");

# AUTH INFORMATION FOR TESTING
my $user_id='kbasepromuser1';
my $password='open4me!';
my $workspace_name="active_prom_test_workspace";
my $token = Bio::KBase::AuthToken->new(user_id => $user_id, password => $password);
ok(defined $token,"auth could get token");

# READ THE LOCAL CONFIG FILE FOR URLS  (IS THERE A BETTER WAY TO FIND THE FILE THAN TO JUST GO THERE????)
my $c = Config::Simple->new();
$c->read("deploy.cfg");
ok(defined $c->param("prom_service.workspace"), "workspace url found");
my $workspace_url =$c->param("prom_service.workspace");
ok(defined $c->param("prom_service.fba"), "FBA url found");
my $fba_url =$c->param("prom_service.fba");
my $test_expression_data = 't/client-tests/sample_boolean_expression_data.txt';
my $test_mapping_file = 't/client-tests/sample_id_mapping.txt';


# 0) BOOTUP THE PROM CLIENT (HOW ELSE CAN I INJECT THE CONFIG LOCATION IN A TEST SCRIPT ?!?!?!?)
use Server;
$ENV{PROM_DEPLOYMENT_CONFIG}='deploy.cfg';
$ENV{PROM_DEPLOYMENT_SERVICE_NAME}='prom_service';
my ($pid, $url) = Server::start('PROM');
#my $url = "http://localhost:7069"; my $pid = '??';
print "-> attempting to connect to:'".$url."' with PID=$pid\n";
my $prom = Bio::KBase::PROM::Client->new($url, user_id=>$user_id, password=>$password);
ok(defined($prom),"instantiating PROM client");


## 1) CREATE A WORKSPACE IF IT DOES NOT EXIST
my $ws = Bio::KBase::workspaceService::Client->new($workspace_url);
my $ws_list = $ws->list_workspaces( { auth=>$token->token() } );
my $found = 0;
foreach my $ws_name (@$ws_list) {
    if($ws_name->[0] eq $workspace_name) { $found=1; }
}
if( $found != 1 ) {
    my $create_workspace_params = {
        workspace => $workspace_name,
        default_permission => 'w',
        auth => $token->token()
    };
    my $workspace_meta = $ws->create_workspace($create_workspace_params);
    ok(defined $workspace_meta, "workspace creation");
    print "Created new workspace: \n".Dumper($workspace_meta)."\n";
} else {
    ok(1, "workspace already exists");
}

#
## 2) CREATE A NEW EXPRESSION DATA COLLECTION
my $expression_data_collection_id; my $status;
($status, $expression_data_collection_id) = $prom->create_expression_data_collection($workspace_name, $token->token());
ok($expression_data_collection_id,"expression collection id defined");
ok($expression_data_collection_id ne "","expression collection id not empty");
print "STATUS: \n$status\n";
print "RETURNED ID: $expression_data_collection_id\n";


## 3) READ DATA FILE AND ATTACH THE DATA TO THE EXPRESSION DATA COLLECTION
open(my $IN, $test_expression_data);
ok($IN,"opening test expression data");
my $UUID=new Data::UUID;
my $expression_data=[]; my @expression_ws_ids; my @features; 
my $line_number=0; my $line='';
while (<$IN>) {
        $line_number++;
	$line = $_; chomp($line);
        if($line ne '') {
            my @tokens = split("\t",$line);
            my $row_header = shift @tokens;
            if($line_number==1) {
                @features = @tokens;
            } else {
                # read the on/off calls
                my $on_off_call = {};
                for(my $k = 0; $k < scalar(@tokens); $k++) {
                    $on_off_call->{$features[$k]} = $tokens[$k];
                }
                #set up and save the object
                my $random_id = $UUID->create_str();
                my $data = {
                    id=> $random_id,
                    on_off_call=>$on_off_call,
                    data_source=>'local_file',
                    data_source_id=>$row_header
                };
                push @$expression_data, $data;
            }
        }
}
close $IN;
# Ok, we can finally try to load the data
$status=$prom->add_expression_data_to_collection($expression_data, $expression_data_collection_id, $workspace_name, $token->token());
ok($status,"add_expression_data_to_collection returned a status message");
ok($status ne "","that status message was not empty");
print "STATUS: \n$status\n";


# 4) CONVERT THE NAMESPACE OF THE EXPRESSION DATA SET
open($IN, $test_mapping_file);
ok($IN,"opening sample feature mapping data");
my $new_feature_names = {};
while (<$IN>) {
	$line = $_; chomp($line);
        if($line ne '') {
            my @tokens = split("\t",$line);
            $new_feature_names->{$tokens[0]} = $tokens[1];
        }
}
close $IN;


#my $expression_data_collection_id = '0179188A-69B3-11E2-ACFF-64D2B2C0258E';
$status=$prom->change_expression_data_namespace($expression_data_collection_id, $new_feature_names, $workspace_name, $token->token());
ok($status,"change_expression_data_namespace returned a status message");
ok($status ne "","that status message was not empty");
print "STATUS: \n$status\n";



## 5) DELETE THE WORKSPACE
my $delete_workspace_params = {
    workspace => $workspace_name,
    auth => $token->token()
};
my $workspace_meta=$ws->delete_workspace($delete_workspace_params);
ok(defined $workspace_meta, "workspace deletion");
print "Deleted workspace: \n".Dumper($workspace_meta)."\n";

done_testing();
