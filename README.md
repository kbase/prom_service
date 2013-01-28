
PROM (Probabilistic Regulation of Metabolism) Service
-----------------------------------------------------------

This service enables the creation of FBA model constraint objects that are based on regulatory
networks and expression data, as described in [1].  Constraints are constructed by either automatically
aggregating necessary information from the CDS (if available for a given genome), or by adding user
expression and regulatory data.  PROM provides the capability to simulate transcription factor knockout
phenotypes.  PROM model constraint objects are created in a user's workspace, and can be operated on and
used in conjunction with an FBA model with the KBase FBA Modeling Service.

[1] Chandrasekarana S. and Price ND. Probabilistic integrative modeling of genome-scale metabolic and
regulatory networks in Escherichia coli and Mycobacterium tuberculosis. PNAS (2010) 107:17845-50.

AUTHORS:
----------------------
Michael Sneddon (mwsneddon@lbl.gov)
Matt DeJongh (dejongh@hope.edu)



DEPLOYMENT INSTRUCTIONS
--------------------------

Update the 'deploy.cfg' file with the endpoints of the services you wish to deploy
against.  Currently they are configured to point to development servers.

Deploy using the standard kbase deployment process after the dev_container is
configured and other dependent modules are checked out (see DEPENDENCIES file),
that is:

cd /kb/dev_container/modules
make
make deploy
cd /kb/deployment
source user-env.sh
cd /kb/deployment/services/prom_service
./start_service


TESTING INSTRUCTIONS
-------------------------

NOTE! tests of this service rely on deploying against compatible FBA modeling services,
workspace services, regulation service and the CDS.  Testing of the methods requires
retrievial of data from each of these services and interaction with each of these
services.  Thus, tests of this module are necessarily integration tests!!!

To test the deployment:

cd /kb/dev_container/modules/prom_service
make test



