/*
PROM (Probabilistic Regulation of Metabolism) Service

This service enables the creation of FBA model objects which include constraints based on regulatory
networks and expression data, as described in [1].  Constraints are constructed by either automatically
aggregating necessary information from the CDS (if available for a given genome), or by adding user
expression and regulatory data.  PROM provides the capability to simulate transcription factor knockout
phenotypes.  PROM model objects are created in a user's workspace, and can be operated on and simulated
with the KBase FBA Modeling Service.

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
    
    /* A workspace ID for an fba model */
    typedef string fbamodel_id;

    /* A workspace ID for a gene expression data object. */
    typedef string boolean_gene_expression_data_id;

    /* A workspace id for a set of expression data on/off calls needed by PROM */
    typedef string expression_data_collection_id;
    
    /* A workspace ID for a regulatory network object, needed by PROM */
    typedef string regulatory_network_id;
    
    /* The ID of a regulome model as registered with the Regulation service */
    typedef string regulomeModelId;
    
    /* Status message used by this service to provide information on the final status of a step  */
    typedef string status;
    
    /* A workspace ID for the prom model object, used to access any models created by this service in
    a user's workpace */
    typedef string prom_model_id;
    
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
        source_id expression_data_source_id  - the id of the data ob
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
    imported here. NOTE 2: feature_id may have to be changed to be a more general ID, as models could potentially be
    loaded that are not in the kbase namespace. Note then that in this case everything, including expression data
    and the fba model must be in the same namespace. NOTE: this data object should be migrated to the Regulation
    service, and simply imported here.
    
        feature_id transcriptionFactor  - the genome feature that is the regulator
        feature_id transcriptionTarget  - the genome feature that is the target of regulation
        float probabilityTTonGivenTFoff - the probability that the transcriptional target is ON, given that the
                                          transcription factor is not expressed, as defined in Candrasekarana &
                                          Price, PNAS 2010 and used to predict cumulative effects of multiple
                                          regulatory interactions with a single target.
        float probabilityTTonGivenTFon - the probability that the transcriptional target is ON, given that the
                                          transcription factor is expressed
    */
    typedef structure {
        feature_id transcriptionFactor;
        feature_id transcriptionTarget;
        float probabilityTTonGivenTFoff;
        float probabilityTTonGivenTFon;
    } regulatory_interaction;
    
    /* A collection of regulatory interactions that together form a regulatory network. This is an extremely
    simplified data object for use in constructing a PROM model.  NOTE: this data object should be migrated to
    the Regulation service, and simply imported here. */
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


    /* DEPRICATED ALREADY!:
    This method automatically constructs, if possible, an FBA model in the authenticated user's workspace that
    includes PROM constraints.  Regulatory interactions are retrieved from the regulation service, and exression
    data is compiled directly from the CDM.  A preconstructed FBA model cooresponding to the genome is also
    retrieved from the CDM if the other data exists.  This method returns a status message that begins with either
    'success' or 'failure', followed by potentially a long set of log or error messages.  If the method was
    successful, then a valid fbamodel_id is returned and which can be used to reference the new model object. */
    funcdef create_from_genome(genome_id genome) returns (status,fbamodel_id);
    
    
    
    /* This method takes a given genome id, and retrieves experimental expression data (if any) for the genome from
    the CDM.  It then uses this expression data to construct an expression_data_collection in the current workspace.
    Note that this method may take a long time to complete if there is a lot of CDM data for this genome.  Also note
    that the current implementation relies on on/off calls being stored in the CDM (correct as of 12/2012).  This will
    almost certainly change, but that means that the on/off calling algorithm must be added to this method, or
    better yet implemented in the expression data service. */
    funcdef retrieve_expression_data(genome_id id, workspace_name workspace_name, auth_token token) returns (status,expression_data_collection_id);
    /*should use type compiler auth, but for now we just use a bearer token so we can pass it to workspace services*/
    /* funcdef retrieve_expression_data(genome_id id, workspace_name workspace_name) returns (status,expression_data_collection_id) authentication required; */
    
    
    
    
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
    how to retrieve a list of models for your genome, and how to propagate existing models to build a new model for your genome. */
    funcdef retrieve_regulatory_network_data(regulomeModelId id) returns (status,regulatory_network_id);
    
    /* Given your own regulatory network for a given genome, load it into the workspace so that it can be used to construct a PROM
    model. Make sure your IDs for each gene are consistant with your FBA model and your gene expression data! */
    funcdef load_regulatory_network_data(regulomeModelId id) returns (status,regulatory_network_id);
    
    
    /* Once you have loaded gene expression data and a regulatory network and have created an fba model for your genome, then
    you can use this method to create add PROM contraints to the FBA model, thus creating a PROM model.  This method will then return
    you the ID of the PROM model object created in your workspace.  The PROM Model object can then be simulated, visualized, edited, etc.
    using methods from the FBAModeling Service. */
    funcdef create_prom_model(expression_data_collection_id e_id, regulatory_network_id r_id, fbamodel_id fba_id) returns (status, prom_model_id);
    

};