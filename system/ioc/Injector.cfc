<!-----------------------------------------------------------------------
********************************************************************************
Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldbox.org | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author 	    :	Luis Majano
Description :
	The WireBox injector is the pivotal class in WireBox that performs
	dependency injection.  It can be used standalone or it can be used in conjunction
	of a ColdBox application context.  It can also be configured with a mapping configuration
	file called a binder, that can provide object/mappings and configuration data.
	
	Easy Startup:
	injector = new coldbox.system.ioc.Injector();
	
	Binder Startup
	injector = new coldbox.system.ioc.Injector(new MyBinder());
	
	Binder Path Startup
	injector = new coldbox.system.ioc.Injector("config.MyBinder");

----------------------------------------------------------------------->
<cfcomponent hint="A WireBox Injector: Builds the graphs of objects that make up your application." output="false" serializable="false">

<!----------------------------------------- CONSTRUCTOR ------------------------------------->			
		
	<!--- init --->
	<cffunction name="init" access="public" returntype="Injector" hint="Constructor. If called without a configuration binder, then WireBox will instantiate the default configuration binder found in: coldbox.system.ioc.config.DefaultBinder" output="false" >
		<cfargument name="binder" 		required="false" default="coldbox.system.ioc.config.DefaultBinder" hint="The WireBox binder or data CFC instance or instantiation path to configure this injector with">
		<cfargument name="properties" 	required="false" default="#structNew()#" hint="A structure of binding properties to passthrough to the Binder Configuration CFC" colddoc:generic="struct">
		<cfargument name="coldbox" 		required="false" hint="A coldbox application context that this instance of WireBox can be linked to, if not using it, we just ignore it." colddoc:generic="coldbox.system.web.Controller">
		<cfscript>
			// Setup Available public scopes
			this.SCOPES = createObject("component","coldbox.system.ioc.Scopes");
			// Setup Available public types
			this.TYPES = createObject("component","coldbox.system.ioc.Types");
		
			// Prepare Injector instance
			instance = {
				// Java System
				javaSystem = createObject('java','java.lang.System'),	
				// Utility class
				utility  = createObject("component","coldbox.system.core.util.Util"),
				// Version
				version  = "1.0.0",	 
				// The Configuration Binder object
				binder   = "",
				// ColdBox Application Link
				coldbox  = "",
				// LogBox Link
				logBox   = "",
				// CacheBox Link
				cacheBox = "",
				// Event Manager Link
				eventManager = "",
				// Configured Event States
				eventStates = [
					"afterInjectorConfiguration", 	// X once injector is created and configured
					"beforeInstanceCreation", 		// Before an injector creates or is requested an instance of an object, the mapping is passed.
					"afterInstanceInitialized",		// once the constructor is called and before DI is performed
					"afterInstanceCreation", 		// once an object is created, initialized and done with DI
					"beforeInstanceInspection",		// X before an object is inspected for injection metadata
					"afterInstanceInspection"		// X after an object has been inspected and metadata is ready to be saved
				],
				// LogBox and Class Logger
				logBox  = "",
				log		= "",
				// Parent Injector
				parent = "",
				// LifeCycle Scopes
				scopes = {}
			};
			
			// Prepare instance ID
			instance.injectorID = instance.javaSystem.identityHashCode(this);
			// Prepare Lock Info
			instance.lockName = "WireBox.Injector.#instance.injectorID#";
			
			// Configure the injector for operation
			configure( arguments.binder, arguments.properties);
			
			return this;
		</cfscript>
	</cffunction>
				
	<!--- configure --->
	<cffunction name="configure" output="false" access="public" returntype="void" hint="Configure this injector for operation, called by the init(). You can also re-configure this injector programmatically, but it is not recommended.">
		<cfargument name="binder" 		required="true" hint="The configuration binder object or path to configure this Injector instance with" colddoc:generic="coldbox.system.ioc.config.Binder">
		<cfargument name="properties" 	required="true" hint="A structure of binding properties to passthrough to the Configuration CFC" colddoc:generic="struct">
		<cfscript>
			var key 			= "";
			var iData			= {};
			var withColdbox 	= isColdBoxLinked();
		</cfscript>
		
		<!--- Lock For Configuration --->
		<cflock name="#instance.lockName#" type="exclusive" timeout="30" throwontimeout="true">
			<cfscript>
			if( withColdBox ){ 
				// Link ColdBox
				instance.coldbox = arguments.coldbox;
				// link LogBox
				instance.logBox  = instance.coldbox.getLogBox();
				// Configure Logging for this injector
				instance.log = instance.logBox.getLogger( this );
				// Link CacheBox
				instance.cacheBox = instance.coldbox.getCacheBox();
				// Link Event Manager
				instance.eventManager = instance.coldbox.getInterceptorService();
				// Link Interception States
				instance.eventManager.appendInterceptionPoints( arrayToList(instance.eventStates) ); 
			}	
			
			// Store binder object built accordingly to our binder building procedures
			instance.binder = buildBinder( arguments.binder, arguments.properties );
			
			// Create local cache, logging and event management if not coldbox context linked.
			if( NOT withColdbox ){ 
				// Running standalone, so create our own logging first
				configureLogBox( instance.binder.getLogBoxConfig() );
				// Create local CacheBox reference
				configureCacheBox( instance.binder.getCacheBoxConfig() ); 
				// Create local event manager
				configureEventManager();
				// Register All Custom Listeners
				registerListeners();
			}
			
			// Create our object builder
			instance.builder = createObject("component","coldbox.system.ioc.Builder").init( this );
			
			// Register Life Cycle Scopes
			registerScopes();
			
			// TODO: Register DSLs
			// registerDSLs();
		
			// Parent Injector declared
			if( isObject(instance.binder.getParentInjector()) ){
				setParent( instance.binder.getParentInjector() );
			}
			
			// Scope registration if enabled?
			if( instance.binder.getScopeRegistration().enabled ){
				doScopeRegistration();
			}
			
			// process mappings for metadata and initialization.
			instance.binder.processMappings();
			
			// Announce To Listeners we are online
			iData.injector = this;
			instance.eventManager.processState("afterInjectorConfiguration",iData);
			</cfscript>
		</cflock>
	</cffunction>

	<!--- getInstance --->
    <cffunction name="getInstance" output="false" access="public" returntype="any" hint="Locates, Creates, Injects and Configures an object model instance">
    	<cfargument name="name" 			required="true" 	hint="The mapping name or CFC instance path to try to build up"/>
		<cfargument name="dsl"				required="false" 	hint="The dsl string to use to retrieve the instance model object, mutually exclusive with 'name'"/>
		<cfargument name="initArguments" 	required="false" 	hint="The constructor structure of arguments to passthrough when initializing the instance" colddoc:generic="struct"/>
		<cfscript>
			var instancePath 	= "";
			var mapping 		= "";
			var target			= "";
			var iData			= {};
			
			// Get by DSL?
			if( structKeyExists(arguments,"dsl") ){
				// TODO: Get by DSL
			}
			
			// Check if Mapping Exists?
			if( NOT instance.binder.mappingExists(arguments.name) ){
				// No Mapping exists, let's try to locate it first. We are now dealing with request by conventions
				// This is done once per instance request as then mappings are cached
				instancePath = locateInstance(arguments.name);
				// If Empty Throw Exception
				if( NOT len(instancePath) ){
					instance.log.error("Requested instance:#arguments.name# was not located in any declared scan location(s): #structKeyList(instance.binder.getScanLocations())# or full CFC path");
					getUtil().throwit(message="Requested instance not found: '#arguments.name#'",
									  detail="The instance could not be located in any declared scan location(s) (#structKeyList(instance.binder.getScanLocations())#) or full path location",
									  type="Injector.InstanceNotFoundException");
				}
				// Let's create a mapping for this requested convention name+path as it is the first time we see it
				registerNewInstance(arguments.name, instancePath);
			}
			
			// Get Requested Mapping (Guaranteed to exist now)
			mapping = instance.binder.getMapping( arguments.name );
			
			// Check if the mapping has been discovered yet, and if it hasn't it must be autowired enabled in order to process.
			if( NOT mapping.isDiscovered() AND mapping.isAutowire() ){ 
				// announce inspection
				iData = {mapping=mapping,binder=instance.binder};
				instance.eventManager.process("beforeInstanceInspection",iData);
				// process inspection of instance
				mapping.process( instance.binder );
				// announce it 
				instance.eventManager.process("afterInstanceInspection",iData);
			}
			
			// scope persistence check
			if( NOT structKeyExists(instance.scopes, mapping.getScope()) ){
				instance.log.error("The mapping scope: #mapping.getScope()# is invalid and not registered in the valid scopes: #structKeyList(instance.scopes)#");
				getUtil().throwit(message="Requested mapping scope: #mapping.getScope()# is invalid",
								  detail="The registered valid object scopes are #structKeyList(instance.scopes)#",
								  type="Injector.InvalidScopeException");
			}
			
			// Request object from scope now, we now have it from the scope created, initialized and wired
			target = instance.scopes[ mapping.getScope() ].getFromScope( mapping );
			
			// Process Provider Methods
			
			// Announce creation, initialization and DI magicfinicitation!
			iData = {mapping=arguments.mapping,target=target};
			instance.eventManager.process("afterInstanceCreation",iData);
			
			return target;
		</cfscript>
    </cffunction>
	
	<!--- buildInstance --->
    <cffunction name="buildInstance" output="false" access="public" returntype="any" hint="Build an instance, this is called from registered scopes only as they provide locking and transactions">
    	<cfargument name="mapping" required="true" hint="The mapping to construct" colddoc:generic="coldbox.system.ioc.config.Mapping">
    	<cfscript>
    		var thisMap = arguments.mapping;
			var oModel	= "";
			var iData	= "";
			
			// before construction event
			iData = {mapping=arguments.mapping};
			instance.eventManager.process("beforeInstanceCreation",iData);
			
    		// determine construction type
    		switch( thisMap.getType() ){
				case "cfc" : {
					oModel = instance.builder.buildCFC( thisMap ); break;
				}
				case "java" : {
					oModel = instance.builder.buildJavaClass( thisMap ); break;
				}
				case "webservice" : {
					oModel = instance.builder.buildWebservice( thisMap ); break;
				}
				case "constant" : {
					oModel = thisMap.getValue(); break;
				}
				case "rss" : {
					oModel = instance.builder.buildFeed( thisMap ); break;
				}
				case "dsl" : {
					oModel = instance.builder.buildDSLDependency( thisMap.getDSL() ); break;
				}
				default: { getUtil().throwit(message="Invalid Construction Type: #thisMap.getType()#",type="Injector.InvalidConstructionType"); }
			}		
			
			// log data
			if( instance.log.canDebug() ){
				instance.log.debug("Instance object built: #arguments.mapping.getMemento().toString()#");
			}
			
			// announce afterInstanceInitialized
			iData = {mapping=arguments.mapping,target=oModel};
			instance.eventManager.process("afterInstanceInitialized",iData);
			
			return oModel;
		</cfscript>
    </cffunction>
	
	<!--- registerNewInstance --->
    <cffunction name="registerNewInstance" output="false" access="private" returntype="void" hint="Register a new requested mapping object instance">
    	<cfargument name="name" 		required="true" hint="The name of the mapping to register"/>
		<cfargument name="instancePath" required="true" hint="The path of the mapping to register">
    	
    	<!--- Register new instance mapping --->
    	<cflock name="Injector.RegisterNewInstance.#hash(arguments.instancePath)#" type="exclusive" timeout="20" throwontimeout="true">
    		<!--- double lock for concurrency --->
    		<cfif NOT instance.binder.mappingExists(arguments.name)>
    			<cfset instance.binder.map(arguments.name).to(arguments.instancePath)>
    		</cfif>
		</cflock>
		
    </cffunction>
		
	<!--- containsInstance --->
    <cffunction name="containsInstance" output="false" access="public" returntype="any" hint="Checks if this injector can locate a model instance or not" colddoc:generic="boolean">
    	<cfargument name="name" required="true" hint="The object name or alias to search for if this container can locate it or has knowledge of it"/>
		<cfscript>
			// check if we have a mapping first
			if( instance.binder.mappingExists(arguments.name) ){ return true; }
			// check if we can locate it?
			if( len(locateInstance(arguments.name)) ){ return true; }
			// NADA!
			return false;		
		</cfscript>
    </cffunction>
		
	<!--- locateInstance --->
    <cffunction name="locateInstance" output="false" access="public" returntype="any" hint="Tries to locate a specific instance by scanning all scan locations and returning the instantiation path. If model not found then the returned instantiation path will be empty">
    	<cfargument name="name" required="true" hint="The model instance name to locate">
		<cfscript>
			var scanLocations		= instance.binder.getScanLocations();
			var thisScanPath		= "";
			var CFCName				= replace(arguments.name,".","/","all") & ".cfc";
			
			// Check Scan Locations In Order
			for(thisScanPath in scanLocations){
				// Check if located? If so, return instantiation path
				if( fileExists( scanLocations[thisScanPath] & CFCName ) ){
					if( instance.log.canDebug() ){ instance.log.debug("Instance: #arguments.name# located in #thisScanPath#"); }
					return thisScanPath & "." & arguments.name;
				}
			}

			// Not found, so let's do full namespace location
			if( fileExists( expandPath("/" & CFCName) ) ){
				if( instance.log.canDebug() ){ instance.log.debug("Instance: #arguments.name# located as is."); }
				return arguments.name;
			}
			
			// debug info, NADA found!
			if( instance.log.canDebug() ){ instance.log.debug("Instance: #arguments.name# was not located anywhere"); }
			
			return "";			
		</cfscript>
    </cffunction>
	
	<!--- autowire --->
    <cffunction name="autowire" output="false" access="public" returntype="any" hint="I wire up target objects with dependencies either by mappings or a-la-carte autowires">
    	<cfargument name="target" 				required="true" 	hint="The target object to wire up"/>
		<cfargument name="mapping" 				required="false" 	hint="The object mapping with all the necessary wiring metadata. Usually passed by scopes and not a-la-carte autowires" colddoc:generic="coldbox.system.ioc.config.Mapping"/>
		<cfargument name="targetID" 			required="false" 	hint="A unique identifier for this target to wire up. Usually a class path or file path should do. If none is passed we will get the id from the passed target via introspection but it will slow down the wiring"/>
    	<cfargument name="annotationCheck" 		required="false" 	default="false" hint="This value determines if we check if the target contains an autowire annotation in the cfcomponent tag: autowire=true|false, it will only autowire if that metadata attribute is set to true. The default is false, which will autowire anything automatically." colddoc:generic="Boolean">
		<cfscript>
			// Targets
			var targetObject 	= arguments.target;
			var targetCacheKey 	= arguments.targetID;
			var metaData 		= "";
			
			// Dependencies
			var thisDependency = instance.NOT_FOUND;

			// Metadata entry structures
			var mdEntry 			= "";
			var targetDIEntry 		= "";
			var dependenciesLength 	= 0;
			var x 					= 1;
			var tmpBean 			= "";	
			
			
			var thisMap				= "";
			var md					= "";
			
			// Do we have a mapping? Or is this a-la-carte wiring
			if( NOT structKeyExists(arguments,"mapping") ){
				// no mapping, so we need to build one for the incoming wiring.
				// do we have id?
				if( NOT structKeyExists(arguments,"targetID") ){
					md = getMetadata(arguments.target);
					arguments.targetID = md.name;
				}
				else{
					md = getMetadata(arguments.target);
				}
				
				// verify instance, if already mapped, then throw exceptions
				if( instance.binder.mappingExists(arguments.targetID) ){
					instance.utility.throwit(message="The autowire target sent: #arguments.targetID# is mapped already",
											 detail="Cannot override a mapping, please verify your definitions.",
											 type="Injector.DoubleMappingException");
				}
				
				// register new mapping instance
				registerNewInstance(arguments.targetID,md.path);
				// get Mapping
				arguments.mapping = instance.binder.getMapping( arguments.targetID );
				// process it
				arguments.mapping.process( instance.binder, md );
				// prepare it with some mixers for wiring
				instance.utility.getMixerUtil().start( arguments.target );
			}
			
			// Set local variable for easy reference
			thisMap = arguments.mapping;

			// Only autowire if no annotation check or if there is one, make sure the mapping is set for autowire
			if ( (arguments.annotationCheck eq false) OR (arguments.annotationCheck AND thisMap.isAutowire()) ){
	
				// Bean Factory Awareness
				if( structKeyExists(targetObject,"setBeanFactory") ){
					targetObject.setBeanFactory( this );
				}
				if( structKeyExists(targetObject,"setInjector") ){
					targetObject.setInjector( this );
				}
				// ColdBox Context Awareness
				if( structKeyExists(targetObject,"setColdBox") ){
					targetObject.setColdBox( getColdBox() );
				}
	
				// Dependencies Length
				dependenciesLength = arrayLen(targetDIEntry.dependencies);
				if( dependenciesLength gt 0 ){
					// Let's inject our mixins
					instance.mixerUtil.start(targetObject);
	
					// Loop over dependencies and inject
					for(x=1; x lte dependenciesLength; x=x+1){
						// Get Dependency
						thisDependency = getDSLDependency(definition=targetDIEntry.dependencies[x]);
	
						// Was dependency Found?
						if( isSimpleValue(thisDependency) and thisDependency eq instance.NOT_FOUND ){
							if( log.canDebug() ){
								log.debug("Dependency: #targetDIEntry.dependencies[x].toString()# Not Found when wiring #getMetadata(arguments.target).name#");
							}
							continue;
						}
	
						// Inject dependency
						injectBean(targetBean=targetObject,
								   beanName=targetDIEntry.dependencies[x].name,
								   beanObject=thisDependency,
								   scope=targetDIEntry.dependencies[x].scope);
	
						if( log.canDebug() ){
							log.debug("Dependency: #targetDIEntry.dependencies[x].toString()# --> injected into #getMetadata(targetObject).name#.");
						}
					}//end for loop of dependencies.
	
					// Process After ID Complete
					processAfterCompleteDI(targetObject,onDICompleteUDF);
	
				}// if dependencies found.
			}//if autowiring
	</cfscript>
    </cffunction>
	
	<!--- Inject Bean --->
	<cffunction name="injectBean" access="private" returntype="void" output="false" hint="Inject a model object with dependencies via setters or property injections">
		<cfargument name="target"  	 		required="true" hint="The target that will be injected with dependencies" />
		<cfargument name="propertyName"  	required="true" hint="The name of the property to inject"/>
		<cfargument name="propertyObject" 	required="true" hint="The object to inject" />
		<cfargument name="scope" 			required="true" hint="The scope to inject a property into, if any else empty">
		
		<cfset var argCollection = structnew()>
		<cfset argCollection[arguments.propertyName] = arguments.propertyObject>
		
		<!--- Property or Setter --->
		<cfif len(arguments.scope) eq 0>
			<!--- Call our mixin invoker: setterMethod--->
			<cfinvoke component="#arguments.target#" method="invokerMixin">
				<cfinvokeargument name="method"  		value="set#arguments.propertyName#">
				<cfinvokeargument name="argCollection"  value="#argCollection#">
			</cfinvoke>
		<cfelse>
			<!--- Call our property injector mixin --->
			<cfinvoke component="#arguments.target#" method="injectPropertyMixin">
				<cfinvokeargument name="propertyName"  	value="#arguments.propertyName#">
				<cfinvokeargument name="propertyValue"  value="#arguments.propertyObject#">
				<cfinvokeargument name="scope"			value="#arguments.scope#">
			</cfinvoke>
		</cfif>
	</cffunction>
	
	<!--- setParent --->
    <cffunction name="setParent" output="false" access="public" returntype="void" hint="Link a parent Injector with this injector">
    	<cfargument name="injector" required="true" hint="A WireBox Injector to assign as a parent to this Injector" colddoc:generic="coldbox.system.ioc.Injector">
    	<cfset instance.parent = arguments.injector>
    </cffunction>
	
	<!--- hasParent --->
    <cffunction name="hasParent" output="false" access="public" returntype="any" hint="Checks if this Injector has a defined parent injector" colddoc:generic="boolean">
    	<cfreturn (isObject(instance.parent))>
    </cffunction>
	
	<!--- getParent --->
    <cffunction name="getParent" output="false" access="public" returntype="any" hint="Get a reference to the parent injector, else an empty string" colddoc:generic="coldbox.system.ioc.Injector">
    	<cfreturn instance.parent>
    </cffunction>
	
	<!--- getObjectPopulator --->
    <cffunction name="getObjectPopulator" output="false" access="public" returntype="any" hint="Get an object populator useful for populating objects from JSON,XML, etc." colddoc:generic="coldbox.system.core.dynamic.BeanPopulator">
    	<cfreturn createObject("component","coldbox.system.core.dynamic.BeanPopulator").init()>
    </cffunction>
	
	<!--- getColdbox --->
    <cffunction name="getColdbox" output="false" access="public" returntype="any" hint="Get the instance of ColdBox linked in this Injector. Empty if using standalone version" colddoc:generic="coldbox.system.web.Controller">
    	<cfreturn instance.coldbox>
    </cffunction>
	
	<!--- isColdBoxLinked --->
    <cffunction name="isColdBoxLinked" output="false" access="public" returntype="any" hint="Checks if Coldbox application context is linked" colddoc:generic="boolean">
    	<cfreturn isObject(instance.coldbox)>
    </cffunction>
	
	<!--- getCacheBox --->
    <cffunction name="getCacheBox" output="false" access="public" returntype="any" hint="Get the instance of CacheBox linked in this Injector. Empty if using standalone version" colddoc:generic="coldbox.system.cache.CacheFactory">
    	<cfreturn instance.cacheBox>
    </cffunction>
	
	<!--- isCacheBoxLinked --->
    <cffunction name="isCacheBoxLinked" output="false" access="public" returntype="any" hint="Checks if CacheBox is linked" colddoc:generic="boolean">
    	<cfreturn isObject(instance.cacheBox)>
    </cffunction>

	<!--- getLogBox --->
    <cffunction name="getLogBox" output="false" access="public" returntype="any" hint="Get the instance of LogBox configured for this Injector" colddoc:generic="coldbox.system.logging.LogBox">
    	<cfreturn instance.logBox>
    </cffunction>

	<!--- Get Version --->
	<cffunction name="getVersion" access="public" returntype="any" output="false" hint="Get the Injector's version string.">
		<cfreturn instance.version>
	</cffunction>
	
	<!--- Get the binder config object --->
	<cffunction name="getBinder" access="public" returntype="any" output="false" hint="Get the Injector's configuration binder object" colddoc:generic="coldbox.system.ioc.config.Binder">
		<cfreturn instance.binder>
	</cffunction>
	
	<!--- getInjectorID --->
    <cffunction name="getInjectorID" output="false" access="public" returntype="any" hint="Get the unique ID of this injector">
    	<cfreturn instance.injectorID>
    </cffunction>
	
	<!--- getEventManager --->
    <cffunction name="getEventManager" output="false" access="public" returntype="any" hint="Get the injector's event manager">
 		<cfreturn instance.eventManager>
    </cffunction>

	<!--- getScopeRegistration --->
    <cffunction name="getScopeRegistration" output="false" access="public" returntype="any" hint="Get the structure of scope registration information" colddoc:generic="struct">
    	<cfreturn instance.binder.getScopeRegistration()>
    </cffunction>

	<!--- removeFromScope --->
    <cffunction name="removeFromScope" output="false" access="public" returntype="void" hint="Remove the Injector from scope registration if enabled, else does nothing">
    	<cfscript>
			var scopeInfo 		= instance.binder.getScopeRegistration();
			// if enabled remove.
			if( scopeInfo.enabled ){
				createObject("component","coldbox.system.core.collections.ScopeStorage")
					.init()
					.delete(scopeInfo.key, scopeInfo.scope);
			}
		</cfscript>
    </cffunction>
	
<!----------------------------------------- PRIVATE ------------------------------------->	

	<!--- registerScopes --->
    <cffunction name="registerScopes" output="false" access="private" returntype="void" hint="Register all internal and configured WireBox Scopes">
    	<cfscript>
    		var customScopes 	= instance.binder.getCustomScopes();
    		var key				= "";
			
    		// register no_scope
			instance.scopes["NOSCOPE"] = createObject("component","coldbox.system.ioc.scopes.NoScope").init( this );
			// register singleton
			instance.scopes["SINGLETON"] = createObject("component","coldbox.system.ioc.scopes.Singleton").init( this );
			// is cachebox linked?
			if( isCacheBoxLinked() ){
				instance.scopes["CACHEBOX"] = createObject("component","coldbox.system.ioc.scopes.CacheBox").init( this );
			}
			// CF Scopes and references
			instance.scopes["REQUEST"] 	= createObject("component","coldbox.system.ioc.scopes.CFScopes").init( this );
			instance.scopes["SESSION"] 		= instance.scopes["REQUEST"];
			instance.scopes["SERVER"] 		= instance.scopes["REQUEST"];
			instance.scopes["APPLICATION"] 	= instance.scopes["REQUEST"];
			
			// Debugging
			if( instance.log.canDebug() ){
				instance.log.debug("Registered all internal lifecycle scopes successfully: #structKeyList(instance.scopes)#");
			}
			
			// Register Custom Scopes
			for(key in customScopes){
				instance.scopes[key] = createObject("component",customScopes[key]).init( this );
				// Debugging
				if( instance.log.canDebug() ){
					instance.log.debug("Registered custom scope: #key# (#customScopes[key]#)");
				}
			}			 
		</cfscript>
    </cffunction>
		
	<!--- registerListeners --->
    <cffunction name="registerListeners" output="false" access="private" returntype="void" hint="Register all the configured listeners in the configuration file">
    	<cfscript>
    		var listeners 	= instance.binder.getListeners();
			var regLen		= arrayLen(listeners);
			var x			= 1;
			var thisListener = "";
			
			// iterate and register listeners
			for(x=1; x lte regLen; x++){
				// try to create it
				try{
					// create it
					thisListener = createObject("component", listeners[x].class);
					// configure it
					thisListener.configure( this, listeners[x].properties);
				}
				catch(Any e){
					instance.log.error("Error creating listener: #listeners[x].toString()#", e);
					getUtil().throwit(message="Error creating listener: #listeners[x].toString()#",
									  detail="#e.message# #e.detail# #e.stackTrace#",
									  type="Injector.ListenerCreationException");
				}
				
				// Now register listener
				instance.eventManager.register(thisListener,listeners[x].name);
				
				// debugging
				if( instance.log.canDebug() ){
					instance.log.debug("Injector has just registered a new listener: #listeners[x].toString()#");
				}
			}			
		</cfscript>
    </cffunction>
	
	<!--- doScopeRegistration --->
    <cffunction name="doScopeRegistration" output="false" access="private" returntype="void" hint="Register this injector on a user specified scope">
    	<cfscript>
    		var scopeInfo 		= instance.binder.getScopeRegistration();
			
			// register injector with scope
			createObject("component","coldbox.system.core.collections.ScopeStorage").init().put(scopeInfo.key, this, scopeInfo.scope);
			
			// Log info
			if( instance.log.canDebug() ){
				instance.log.debug("Scope Registration enabled and Injector scoped to: #scopeInfo.toString()#");
			}
		</cfscript>
    </cffunction>
	
	<!--- configureCacheBox --->
    <cffunction name="configureCacheBox" output="false" access="private" returntype="void" hint="Configure a standalone version of cacheBox for persistence">
    	<cfargument name="config" required="true" hint="The cacheBox configuration data structure" colddoc:generic="struct"/>
    	<cfscript>
    		var args 	= structnew();
			var oConfig	= "";
			
			// is cachebox enabled?
			if( NOT arguments.config.enabled ){
				return;
			}
			
			// Do we have a cacheBox reference?
			if( isObject(arguments.config.cacheFactory) ){
				instance.cacheBox = arguments.config.cacheFactory;
				// debugging
				if( instance.log.canDebug() ){
					instance.log.debug("Configured Injector #getInjectorID()# with direct CacheBox instance: #instance.cacheBox.getFactoryID()#");
				}
				return;
			}
			
			// Do we have a configuration file?
			if( len(arguments.config.configFile) ){
				// xml?
				if( listFindNoCase("xml,cfm", listLast(arguments.config.configFile,".") ) ){
					args["XMLConfig"] = arguments.config.configFile;
				}
				else{
					// cfc
					args["CFCConfigPath"] = arguments.config.configFile;
				}
				
				// Create CacheBox
				oConfig = createObject("component","#arguments.config.classNamespace#.config.CacheBoxConfig").init(argumentCollection=args);
				instance.cacheBox = createObject("component","#arguments.config.classNamespace#.CacheFactory").init( oConfig );
				// debugging
				if( instance.log.canDebug() ){
					instance.log.debug("Configured Injector #getInjectorID()# with CacheBox instance: #instance.cacheBox.getFactoryID()# and configuration file: #arguments.config.configFile#");
				}
				return;
			}
			
			// No config file, plain vanilla cachebox
			instance.cacheBox = createObject("component","#arguments.config.classNamespace#.CacheFactory").init();
			// debugging
			if( instance.log.canDebug() ){
				instance.log.debug("Configured Injector #getInjectorID()# with vanilla CacheBox instance: #instance.cacheBox.getFactoryID()#");
			}						
		</cfscript>
    </cffunction>
	
	<!--- configureLogBox --->
    <cffunction name="configureLogBox" output="false" access="private" returntype="void" hint="Configure a standalone version of logBox for logging">
    	<cfargument name="configPath" required="true" hint="The logBox configuration path to use"/>
    	<cfscript>
    		var config 	= ""; 
			var args 	= structnew();
			
			// xml?
			if( listFindNoCase("xml,cfm", listLast(arguments.configPath,".") ) ){
				args["XMLConfig"] = arguments.configPath;
			}
			else{
				// cfc
				args["CFCConfigPath"] = arguments.configPath;
			}
			
			config = createObject("component","coldbox.system.logging.config.LogBoxConfig").init(argumentCollection=args);
			
			// Create LogBox
			instance.logBox = createObject("component","coldbox.system.logging.LogBox").init( config );
			// Configure Logging for this injector
			instance.log = instance.logBox.getLogger( this );	
		</cfscript>
    </cffunction>
	
	<!--- configureEventManager --->
    <cffunction name="configureEventManager" output="false" access="private" returntype="void" hint="Configure a standalone version of a WireBox Event Manager">
    	<cfscript>
    		// create event manager
			instance.eventManager = createObject("component","coldbox.system.core.events.EventPoolManager").init( instance.eventStates );
			// Debugging
			if( instance.log.canDebug() ){
				instance.log.debug("Registered injector's event manager with the following event states: #instance.eventStates.toString()#");
			}
		</cfscript>
    </cffunction>
	
	<!--- Get ColdBox Util --->
	<cffunction name="getUtil" access="public" output="false" returntype="any" hint="Return the core util object" colddoc:generic="coldbox.system.core.util.Util">
		<cfreturn instance.utility>
	</cffunction>
	
	<!--- buildBinder --->
    <cffunction name="buildBinder" output="false" access="private" returntype="any" hint="Load a configuration binder object according to passed in type">
    	<cfargument name="binder" 		required="true" hint="The data CFC configuration instance, instantiation path or programmatic binder object to configure this injector with"/>
		<cfargument name="properties" 	required="true" hint="A map of binding properties to passthrough to the Configuration CFC"/>
		<cfscript>
			var dataCFC = "";
			
			// Check if just a plain CFC path and build it
			if( isSimpleValue(arguments.binder) ){
				arguments.binder = createObject("component",arguments.binder);
			}
			
			// Now decorate it with properties, a self reference, and a coldbox reference if needed.
			arguments.binder.injectPropertyMixin = instance.utility.getMixerUtil().injectPropertyMixin;
			arguments.binder.injectPropertyMixin("properties",arguments.properties,"instance");
			arguments.binder.injectPropertyMixin("injector",this);
			if( isColdBoxLinked() ){
				arguments.binder.injectPropertyMixin("coldbox",getColdBox());
			}
			
			// Check if already a programmatic binder object?
			if( isInstanceOf(arguments.binder, "coldbox.system.ioc.config.Binder") ){
				// Configure it
				arguments.binder.configure();
				// Load it
				arguments.binder.loadDataDSL();
				// Use it
				return arguments.binder;
			}
			
			// If we get here, then it is a simple data CFC, decorate it with a vanilla binder object and configure it for operation
			return createObject("component","coldbox.system.ioc.config.Binder").init(arguments.binder);
		</cfscript>
    </cffunction>
	
</cfcomponent>