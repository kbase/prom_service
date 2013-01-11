/*
PROM (Probabilistic Regulation of Metabolism) Service

This service enables the creation of FBA model constraint objects that are based on regulatory
networks and expression data, as described in [1].  Constraints are constructed by either automatically
aggregating necessary information from the CDS (if available for a given genome), or by adding user
expression and regulatory data.  PROM provides the capability to simulate transcription factor knockout
phenotypes.  PROM model constraint objects are created in a user's workspace, and can be operated on and
used in conjunction with an FBA model with the KBase FBA Modeling Service.

[1] Chandrasekarana S. and Price ND. Probabilistic integrative modeling of genome-scale metabolic and
regulatory networks in Escherichia coli and Mycobacterium tuberculosis. PNAS (2010) 107:17845-50.

created 11/27/2012 - msneddon
*/
module PROM
{

    /* ************************************************************************************* */
    /* * SIMPLE ID AND STRING TYPES **/
    /* ************************************************************************************* */

    /* A KBase ID is a string starting with the characters "kb|".  KBase IDs are typed. The types are
    designated using a short string.  KBase IDs may be hierarchical.  See the standard KBase documentation
    for more information.  */
    typedef string kbase_id;
    
    /* A KBase ID for a genome feature */
    typedef kbase_id feature_id;
    
    /* A KBase ID for a genome */
    typedef kbase_id genome_id;
    
    /* The name of a workspace */
    typedef string workspace_name;

    /* A workspace ID for a gene expression data object. */
    typedef string boolean_gene_expression_data_id;

    /* A workspace id for a set of expression data on/off calls */
    typedef string expression_data_collection_id;
    
    /* A workspace ID for a regulatory network object */
    typedef string regulatory_network_id;
    
    /* Status message used by this service to provide information on the final status of a step  */
    typedef string status;
    
    /* A workspace ID for the prom constraint object, used to access any models created by this service in
    a user's workpace */
    typedef string prom_constraint_id;
    
    /* Specifies the source of a data object, e.g. KBase or MicrobesOnline */
    typedef string source;
    
    /* Specifies the ID of the data object in the source */
    typedef string source_id;
    
    /* The string representation of the bearer token needed to authenticate on the workspace service */
    typedef string auth_token;
    
    
    
    /* ************************************************************************************* */
    /* * EXPRESSION DATA TYPES * */
    /* ************************************************************************************* */
    
    /* Indicates on/off state of a gene, 1=on, -1=off, 0=unknown */
    typedef int on_off_state;
    
    /* A simplified representation of gene expression data under a SINGLE condition. Note that the condition
    information is not explicitly tracked here. also NOTE: this data object should be migrated to the Expression
    Data service, and simply imported here.
    
        mapping<feature_id,on_off_state> on_off_call - a mapping of genome features to on/off calls under the given
                                               condition (true=on, false=off).  It is therefore assumed that
                                               the features are protein coding genes.
        source expression_data_source        - the source of this collection of expression data
        source_id expression_data_source_id  - the id of this data object in the workspace
    */
    typedef structure {
        boolean_gene_expression_data_id id;
        mapping<feature_id,on_off_state> on_off_call;
        source expression_data_source;
        source expression_data_source_id;
    } boolean_gene_expression_data;
    
    /* A collection of gene expression data for a single genome under a range of conditions.  This data is returned
    as a list of IDs for boolean gene expression data objects in the workspace.  This is a simple object for creating
    a PROM Model. NOTE: this data object should be migrated to the Expression Data service, and simply imported here. */
    typedef structure {
        expression_data_collection_id id;
        list<boolean_gene_expression_data_id> expression_data_ids;
    } boolean_gene_expression_data_collection;
    
    
    
    /* ************************************************************************************* */
    /* * REGULATORY NETWORK TYPES * */
    /* ************************************************************************************* */

    /* A simplified representation of a regulatory interaction that also stores the probability of the interaction
    (specificially, as the probability the target is on given that the regulator is off), which is necessary for PROM
    to construct FBA constraints.  NOTE: this data object should be migrated to the Regulation service, and simply
    imported here. NOTE 2: feature_id may actually be a more general ID, as models can potentially be loaded that
    are not in the kbase namespace. In this case everything, including expression data and the fba model must be in
    the same namespace.
    
        feature_id TF            - the genome feature that is the regulator
        feature_id target        - the genome feature that is the target of regulation
        float probTTonGivenTFoff - the probability that the transcriptional target is ON, given that the
                                   transcription factor is not expressed, as defined in Candrasekarana &
                                   Price, PNAS 2010 and used to predict cumulative effects of multiple
                                   regulatory interactions with a single target.  Set to null or empty if
                                   this probability has not been calculated yet.
        float probTTonGivenTFon  - the probability that the transcriptional target is ON, given that the
                                   transcription factor is expressed.    Set to null or empty if
                                   this probability has not been calculated yet.
    */
    typedef structure {
        feature_id TF;
        feature_id target;
        float probabilityTTonGivenTFoff;
        float probabilityTTonGivenTFon;
    } regulatory_interaction;
    
    
    /* A collection of regulatory interactions that together form a regulatory network. This is an extremely
    simplified data object for use in constructing a PROM model.  NOTE: this data object should be migrated to
    the Regulation service, and simply imported here.
    */
    typedef list<regulatory_interaction> regulatory_network;
    
    
    
    /* ************************************************************************************* */
    /* * PROM CONSTRAINTS TYPE * */
    /* ************************************************************************************* */

    /* An object that encapsulates the information necessary to apply PROM-based constraints to an FBA model. This
    includes a regulatory network consisting of a set of regulatory interactions, and a copy of the expression data
    that is required to compute the probability of regulatory interactions.  A prom constraint object can then be
    associated with an FBA model to create a PROM model that can be simulated with tools from the FBAModelingService.
    
        list<regulatory_interaction> regulatory_network           - a collection of regulatory interactions that
                                                                    compose a regulatory network.  Probabilty values
                                                                    are initially set to nan until they are computed
                                                                    from the set of expression experiments.
        list<boolean_gene_expression_data> expression_experiments - a collection of expression data experiments that
                                                                    coorespond to this genome of interest.
    */
    typedef structure {
        regulatory_network regulatory_network;
        expression_data_collection_id expression_data_collection_id;
    } prom_constraint;
    
    


    /* ************************************************************************************* */
    /* * METHODS * */
    /* ************************************************************************************* */

    /*
    This method fetches all gene expression data available in the CDS that is associated with the given genome id.  It then
    constructs an expression_data_collection object in the specified workspace.  The method returns the ID of the expression
    data collection in the workspace, along with a status message that provides details on what was retrieved and if anything
    failed.  If the method does fail, or if there is no data for the given genome, then no expression data collection is
    created and no ID is returned.
    
    Note 1: this method currently can take a long time to complete if there are many expression data sets in the CDS
    Note 2: the current implementation relies on on/off calls stored in the CDM (correct as of 1/2013).  This will almost
    certainly change, at which point logic for making on/off calls will be required as input
    Note 3: this method should be migrated to the expression service, which currently does not exist
    Note 4: this method should use the type compiler auth, but for simplicity  we now just pass an auth token directly.
    */
    funcdef get_expression_data_by_genome(genome_id genome_id, workspace_name workspace_name, auth_token token) returns (status status,expression_data_collection_id expression_data_collection_id);
    
    
    /* funcdef create_expression_data_collection(workspace_name) returns (status, expression_data_collection_id); */
    /* funcdef add_expression_data_to_collection(workspace_name, list<expression_data>); */
    /* funcdef merge_expression_data_collections(list <expression_data_collection_id> collections) returns (status,expression_data_collection_id); */
    
    
    funcdef change_expression_data_namespace(expression_data_collection_id expression_data_collection_id, mapping<string,string> new_feature_names, workspace_name workspace_name, auth_token token) returns (status status, expression_data_collection_id expression_data_collection_id);
    
    
    
    /*
    This method fetches a regulatory network from the regulation service that is associated with the given genome id.  If there
    are multiple regulome models available for the given genome, then the model with the most regulons is selected.  The method
    then constructs a regulatory network object in the specified workspace.  The method returns the ID of the regulatory network
    in the workspace, along with a status message that provides details on what was retrieved and if anything failed.  If the
    method does fail, or if there is no regulome for the given genome, then no regulatory network ID is returned.
    
    Note 1: this method should be migrated to the regulation service
    Note 2: this method should use the type compiler auth, but for simplicity  we now just pass an auth token directly.
    */
    funcdef get_regulatory_network_by_genome(genome_id genome_id, workspace_name workspace_name, auth_token token) returns (status status, regulatory_network_id regulatory_network_id);
    
    /* funcdef add_regulatory_network(workspace_name, regulatory_network); */
    
    
    /*
    Maps the regulatory network stored 
    funcdef change_regulatory_network_namespace(regulatory_network_id regulatory_network_id, mapping<string,string> new_feature_names, workspace_name workspace_name, auth_token token) returns (status status, regulatory_network_id new_regulatory_network_id);
    
    /*
    Once you have loaded gene expression data and a regulatory network for a specific genome, then
    you can use this method to create add PROM contraints to the FBA model, thus creating a PROM model.  This method will then return
    you the ID of the PROM model object created in your workspace.  The PROM Model object can then be simulated, visualized, edited, etc.
    using methods from the FBAModeling Service.
    */
    funcdef create_prom_constraints(expression_data_collection_id e_id, regulatory_network_id r_id, workspace_name workspace_name, auth_token token) returns (status status, prom_constraint_id prom_constraint_id);
    
    
    
    
    
    /* This method allows the end user to upload gene expression data directly to a workspace.  This is useful if, for
    instance, the gene expression data needed is private or not yet uploaded to the CDM.  Note that it is critical that
    the gene ids are the same as the ids used in the FBA model! */
    funcdef load_expression_data(boolean_gene_expression_data_collection data) returns (status,expression_data_collection_id);

    /* Given several expression data collections, this method merges them into a single collection in the workspace, and returns
    the collection id.  This is useful for building a collection which includes both CDM data and data from multiple other sources,
    as the create_prom_model method does not allow multiple expression data collections.
    NOT YET IMPLEMENTED
    funcdef merge_expression_data_collections(list <expression_data_collection_id> collections) returns (status,expression_data_collection_id);
    */
    
    
    /* This method retrieves regulatory network data from the KBase Regulation service based on the Regulome model ID.  This
    model must be defined for the same exact genome with which you are constructing the FBA model.  If a model does not exist for
    your genome, the you have to build it yourself using the Regulation service.  See the Regulation service for more information on
    how to retrieve a list of models for your genome, and how to propagate existing models to build a new model for your genome. 
    funcdef retrieve_regulatory_network_data(regulomeModelId id) returns (status,regulatory_network_id);*/
    
    /* Given your own regulatory network for a given genome, load it into the workspace so that it can be used to construct a PROM
    model. Make sure your IDs for each gene are consistant with your FBA model and your gene expression data! 
    funcdef load_regulatory_network_data(regulomeModelId id) returns (status,regulatory_network_id);*/
    
    
    

};