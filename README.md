
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

Update the 'deploy.cfg' file
