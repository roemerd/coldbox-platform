<!-----------------------------------------------------------------------
********************************************************************************
Copyright 2005-2008 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldboxframework.com | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author     :	Luis Majano
Date        :	9/28/2007
Description :
	This is an interceptor for ses support. This code is based almost totally on
	Adam Fortuna's ColdCourse cfc, which is an AMAZING SES component
	All credits go to him: http://coldcourse.riaforge.com
----------------------------------------------------------------------->
<cfcomponent name="SES"
			 hint="This is a ses support internceptor"
			 output="false"
			 extends="coldbox.system.Interceptor">
				 
<!------------------------------------------- CONSTRUCTOR ------------------------------------------->

	<cfscript>
		/* Reserved Keys as needed for cleanups */
		instance.RESERVED_KEYS = "handler,action,view,viewNoLayout";
		instance.RESERVED_ROUTE_ARGUMENTS = "pattern,regexpattern,matchVariables,packageresolverexempt,patternParams";
	</cfscript>

	<cffunction name="configure" access="public" returntype="void" hint="This is where the ses plugin configures itself." output="false" >
		<cfscript>
			var configFilePath = "/";
			var controller = getController();
			
			/* If AppMapping is not Blank check */
			if( controller.getSetting('AppMapping') neq "" ){
				configFilePath = configFilePath & controller.getSetting('AppMapping') & "/";
			}
			
			/* Setup the default interceptor properties */
			setRoutes( ArrayNew(1) );
			setUniqueURLs(true);
			setEnabled(true);
			setDebugMode(false);
			
			/* Verify the properties */
			if( not propertyExists('configFile') ){
				throw('The configFile property has not been defined. Please define it.','','interceptors.SES.configFilePropertyNotDefined');
			}
			
			/* Setup the config Path */
			configFilePath = configFilePath & reReplace(getProperty('ConfigFile'),"^/","");
			
			/* We are ready to roll. Import config to setup the routes. */
			try{
				include(configFilePath);
			}
			catch(Any e){
				throw("Error including config file: #e.message#",e.detail,"interceptors.SES.executingConfigException");
			}
			
			/* Loose Matching Property: default = false */
			if( not propertyExists('looseMatching') OR NOT isBoolean(getProperty('looseMatching')) ){
				setProperty('looseMatching',false);
			}
			
			/* Validate the base URL */
			if ( len(getBaseURL()) eq 0 ){
				throw('The baseURL property has not been defined. Please define it using the setBaseURL() method.','','interceptors.SES.invalidPropertyException');
			}
			
			/* Save the base URL in the application settings */
			setSetting('sesBaseURL', getBaseURL() );
			setSetting('htmlBaseURL', replacenocase(getBaseURL(),"index.cfm",""));
		</cfscript>
	</cffunction>

<!------------------------------------------- INTERCEPTION POINTS ------------------------------------------->
	
	<!--- Pre execution process --->
	<cffunction name="preProcess" access="public" returntype="void" hint="This is the route dispatch" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="event" 		 required="true" type="any" hint="The event object.">
		<cfargument name="interceptData" required="true" type="struct" hint="interceptData of intercepted info.">
		<!--- ************************************************************* --->
		<cfscript>
			/* Find which route this URL matches */
			var aRoute = "";
			var key = "";
			var cleanedPaths = getCleanedPaths();
			var routedStruct = structnew();
			
			/* Check if active or in proxy mode */
			if ( NOT getEnabled() OR arguments.event.isProxyRequest() )
				return;
			
			/* Set tha we are in ses mode */
			arguments.event.setIsSES(true);
			
			/* Check for invalid URLs if in strict mode */
			if( getUniqueURLs() ){
				checkForInvalidURL( cleanedPaths["pathInfo"] , cleanedPaths["scriptName"], arguments.event );
			}
						
			/* Find a route to dispatch */
			aRoute = findRoute( cleanedPaths["pathInfo"], arguments.event );
			
			/* Now route should have all the key/pairs from the URL we need to pass to our event object */
			for( key in aRoute ){
				/* Reserved Keys Check */
				if( not listFindNoCase(instance.RESERVED_KEYS,key) ){
					/* Save in RC and Routed Struct */
					arguments.event.setValue( key, aRoute[key] );
					routedStruct[key] = aRoute[key];
				}
			}
			
			/* Create Event To Dispatch */
			if( structKeyExists(aRoute,"handler") ){
				/* If no action found, default to the convention */
				if( NOT structKeyExists(aRoute,"action") ){
					aRoute.action = getDefaultFrameworkAction();
				}
				/* Create event */
				rc[getSetting('EventName')] = aRoute.handler & "." & aRoute.action;
			}
			
			/* See if View is Dispatched */
			if( structKeyExists(aRoute,"view") ){
				/* Dispatch the View */
				arguments.event.setViewDispatched(aRoute.view,aRoute.viewNoLayout);
			}
			
			/* Save the Routed Variables */
			arguments.event.setRoutedStruct(routedStruct);
			
			/* Execute Cache Test now that routing has been done. We override, because events are determined until now. */
			getController().getRequestService().EventCachingTest(context=arguments.event);
		</cfscript>
	</cffunction>

<!------------------------------------------- PUBLIC ------------------------------------------->
	
	<!--- AddCourse --->
	<cffunction name="addCourse" access="public" hint="@Deprecated, please use addRoute as this method will be removed eventually." output="false">
		<cfargument name="pattern" 				 type="string" 	required="true"  hint="The pattern to match against the URL." />
		<cfargument name="handler" 				 type="string" 	required="false" hint="The handler to path to execute if passed.">
		<cfargument name="action"  				 type="string" 	required="false" hint="The action to assign if passed.">
		<cfargument name="packageResolverExempt" type="boolean" required="false" default="false" hint="If this is set to true, then the interceptor will not try to do handler package resolving. Else a package will always be resolved.">
		<cfargument name="matchVariables" 		 type="string" 	required="false" hint="A string of name-value pair variables to add to the request collection when this pattern matches. This is a comma delimmitted list. Ex: spaceFound=true,missingAction=onTest">
		<cfset addRoute(argumentCollection=arguments)>
	</cffunction>
	
	<!--- Add a new Route --->
	<cffunction name="addRoute" access="public" hint="Adds a route to dispatch" output="false">
		<!--- ************************************************************* --->
		<cfargument name="pattern" 				 type="string" 	required="true"  hint="The pattern to match against the URL." />
		<cfargument name="handler" 				 type="string" 	required="false" hint="The handler to path to execute if passed.">
		<cfargument name="action"  				 type="string" 	required="false" hint="The action to assign if passed.">
		<cfargument name="packageResolverExempt" type="boolean" required="false" default="false" hint="If this is set to true, then the interceptor will not try to do handler package resolving. Else a package will always be resolved.">
		<cfargument name="matchVariables" 		 type="string" 	required="false" hint="A string of name-value pair variables to add to the request collection when this pattern matches. This is a comma delimmitted list. Ex: spaceFound=true,missingAction=onTest">
		<cfargument name="view"  				 type="string"  required="false" hint="The view to dispatch.  No event will be fired, so handler,action will be ignored.">
		<cfargument name="viewNoLayout"  		 type="boolean"  required="false" default="false" hint="If view is choosen, then you can choose to override and not display a layout with the view. Else the view renders in the assigned layout.">
		<!--- ************************************************************* --->
		<cfscript>
		var thisRoute = structNew();
		var thisPattern = "";
		var arg = 0;
		var x =1;
		var thisRegex = 0;
	
		/* Process all incoming arguments */
		for(arg in arguments){
			if( structKeyExists(arguments,arg) ){ thisRoute[arg] = arguments[arg]; }
		}
		/* Add trailing / to make it easier to parse */
		if( right(thisRoute.pattern,1) IS NOT "/" ){
			thisRoute.pattern = thisRoute.pattern & "/";
		}		
		/* Cleanup initial / */
		if( left(thisRoute.pattern,1) IS "/" ){
			thisRoute.pattern = right(thisRoute.pattern,len(thisRoute.pattern)-1);
		}
		
		/* Check if we have optional args by looking for a ? */
		if( findnocase("?",thisRoute.pattern) ){
			processRouteOptionals(thisRoute);
		}
		else{
			/* Init the regexpattern */
			thisRoute.regexPattern = "";
			thisRoute.patternParams = arrayNew(1);
			/* Process the route as a regex pattern */
			for(x=1; x lte listLen(thisRoute.pattern,"/");x=x+1){
				thisPattern = listGetAt(thisRoute.pattern,x,"/");
				/* Find Numeric PlaceHolder */
				if( findnoCase("-numeric",thisPattern) ){
					/* Convert to Regex Pattern */
					thisRegex = "(" & REReplace(thisPattern, ":.*?-numeric", "[0-9]");
					/* Check Digits */
					if( find("{",thisPattern) ){
						thisRegex = listFirst(thisRegex,"{") & "{#listLast(thisPattern,"{")#)";
					}
					else{
						thisRegex = thisRegex & "+?)";
					}
					/* Add Route Param */
					arrayAppend(thisRoute.patternParams,replace(listFirst(thisPattern,"-"),":",""));
				}
				/* Alpha-Numeric */
				else{
					if( find(":",thisPattern) ){
						thisRegex = "(" & REReplace(thisPattern,":(.[^-])*","[^/]");
						/* Check Digits */
						if( find("{",thisPattern) ){
							thisRegex = listFirst(thisRegex,"{") & "{#listLast(thisPattern,"{")#)";
							arrayAppend(thisRoute.patternParams,replace(listFirst(thisPattern,"{"),":",""));
						}
						else{
							thisRegex = thisRegex & "+?)";
							arrayAppend(thisRoute.patternParams,replace(thisPattern,":",""));
						}
					}
					else{ thisRegex = thisPattern; }
				}
				/* Add it to Pattern */
				thisRoute.regexPattern = thisRoute.regexPattern & thisRegex & "/";
			}
			/* Finally add it to the routing table. */
			ArrayAppend(getRoutes(), thisRoute);
		}
		</cfscript>
	</cffunction>
	
	<!--- Getter/Setter for uniqueURLs --->
	<cffunction name="setUniqueURLs" access="public" output="false" returntype="void" hint="Set the uniqueURLs property">
		<cfargument name="uniqueURLs" type="boolean" required="true" />
		<cfset instance.uniqueURLs = arguments.uniqueURLs />
	</cffunction>
	<cffunction name="getUniqueURLs" access="public" output="false" returntype="boolean" hint="Get uniqueURLs">
		<cfreturn instance.uniqueURLs/>
	</cffunction>
	
	<!--- Interceptor DebugMode --->
	<cffunction name="getdebugMode" access="public" output="false" returntype="boolean" hint="Get the current debug mode for the interceptor">
		<cfreturn instance.debugMode/>
	</cffunction>
	<cffunction name="setdebugMode" access="public" output="false" returntype="void" hint="Set the interceptor into debug mode and log all translations">
		<cfargument name="debugMode" type="boolean" required="true"/>
		<cfset instance.debugMode = arguments.debugMode/>
	</cffunction>
	
	<!--- Setter/Getter for Base URL --->
	<cffunction name="setBaseURL" access="public" output="false" returntype="void" hint="Set the base URL for the application.">
		<cfargument name="baseURL" type="string" required="true" />
		<cfset instance.baseURL = arguments.baseURL />
	</cffunction>
	<cffunction name="getBaseURL" access="public" output="false" returntype="string" hint="Get BaseURL">
		<cfreturn instance.BaseURL/>
	</cffunction>
	
	<!--- Getter/Setter Enabled --->
	<cffunction name="setEnabled" access="public" output="false" returntype="void" hint="Set whether the interceptor is enabled or not.">
		<cfargument name="enabled" type="boolean" required="true" />
		<cfset instance.enabled = arguments.enabled />
	</cffunction>
	<cffunction name="getenabled" access="public" output="false" returntype="boolean" hint="Get enabled">
		<cfreturn instance.enabled/>
	</cffunction>
	
	<!--- Getter routes --->
	<cffunction name="getRoutes" access="public" output="false" returntype="Array" hint="Get the array containing all the routes">
		<cfreturn instance.Routes/>
	</cffunction>	

<!------------------------------------------- PRIVATE ------------------------------------------->
	
	<!--- Set Routes --->
	<cffunction name="setRoutes" access="private" output="false" returntype="void" hint="Internal override of the routes array">
		<cfargument name="Routes" type="Array" required="true"/>
		<cfset instance.Routes = arguments.Routes/>
	</cffunction>
	
	<!--- Get Default Framework Action --->
	<cffunction name="getDefaultFrameworkAction" access="private" returntype="string" hint="Get the default framework action" output="false" >
		<cfreturn getController().getSetting("eventAction",1)>
	</cffunction>
	
	<!--- CGI Element Facade. --->
	<cffunction name="getCGIElement" access="private" returntype="string" hint="The cgi element facade method" output="false" >
		<cfargument name="cgielement" required="true" type="string" hint="The cgi element to retrieve">
		<cfscript>
			return cgi[arguments.cgielement];
		</cfscript>
	</cffunction>
	
	<!--- Package Resolver --->
	<cffunction name="packageResolver" access="private" returntype="any" hint="Resolve handler packages" output="false" >
		<!--- ************************************************************* --->
		<cfargument name="routingString" 	required="true" type="any" hint="The routing string">
		<cfargument name="routeParams" 		required="true" type="any" hint="The route params array">
		<!--- ************************************************************* --->
		<cfscript>
			var root = getSetting("HandlersPath");
			var extRoot = getSetting("HandlersExternalLocationPath");
			var x = 1;
			var newEvent = "";
			var thisFolder = "";
			var foundPaths = "";
			var rString = arguments.routingString;
			var routeParamsLen = ArrayLen(routeParams);
			var returnString = arguments.routingString;
			
			/* Verify if we have a handler on the route params */
			if( findnocase("handler", arrayToList(arguments.routeParams)) ){
				/* Cleanup routing string to position of :handler */
				for(x=1; x lte routeParamsLen; x=x+1){
					if( routeParams[x] neq "handler" ){
						rString = replace(rString,listFirst(rString,"/") & "/","");
					}
					else{
						break;
					}
				}	
				/* Now Find Packaging in our stripped rString */
				for(x=1; x lte listLen(rString,"/"); x=x+1){
					/* Get Folder */
					thisFolder = listgetAt(rString,x,"/");
					/* Check if package exists in convention OR external location */
					if( directoryExists(root & "/" & foundPaths & thisFolder) 
						OR
					    ( len(extRoot) AND directoryExists(extRoot & "/" & foundPaths & thisFolder) ) 
					    ){
						/* Save Found Paths */
						foundPaths = foundPaths & thisFolder & "/";
						/* Save new Event */
						if(len(newEvent) eq 0){
							newEvent = thisFolder & ".";
						}
						else{
							newEvent = newEvent & thisFolder & ".";
						}						
					}//end if folder found
					else{
						//newEvent = newEvent & "." & thisFolder;
						break;
					}//end not a folder.
				}//end for loop
				/* Replace Return String */
				if( len(newEvent) ){
					returnString = replacenocase(returnString,replace(newEvent,".","/","all"),newEvent);
				}					
			}//end if handler found	
			
			return returnString;
		</cfscript>
	</cffunction>
	
	<!--- Serialize a URL --->
	<cffunction name="serializeURL" access="private" output="false" returntype="string" hint="Serialize a URL">
		<!--- ************************************************************* --->
		<cfargument name="formVars" required="false" default="" type="string">
		<cfargument name="event" 	required="true" type="any" hint="The event object.">
		<!--- ************************************************************* --->
		<cfscript>
			var vars = arguments.formVars;
			var key = 0;
			var rc = arguments.event.getCollection();
			
			for(key in rc){
				if( NOT ListFindNoCase("route,handler,action,#getSetting('eventName')#",key) ){
					vars = ListAppend(vars, "#lcase(key)#=#rc[key]#", "&");
				}
			}
			if( len(vars) eq 0 ){
				return "";
			}
			else{
				return "?" & vars;
			}
		</cfscript>
	</cffunction>
	
	<!--- Check for Invalid URL --->
	<cffunction name="checkForInvalidURL" access="private" output="false" returntype="void" hint="Check for invalid URL's">	
		<!--- ************************************************************* --->
		<cfargument name="route" 		required="true" type="any" />	
		<cfargument name="script_name" 	required="true" type="any" />
		<cfargument name="event" 		required="true" type="any" hint="The event object.">
		<!--- ************************************************************* --->
		<cfset var handler = "" />
		<cfset var action = "" />
		<cfset var newpath = "" />
		<cfset var httpRequestData = "">
		<cfset var EventName = getSetting('EventName')>
		<cfset var DefaultEvent = getSetting('DefaultEvent')>
		<cfset var rc = event.getCollection()>
		
		<!--- Get the HTTP Data --->
		<cfset httpRequestData = GetHttpRequestData()/>
		
		<!--- 
		Verify we have uniqueURLs ON, the event var exists, route is empty or index.cfm
		AND
		if the incoming event is not the default OR it is the default via the URL.
		--->
		<cfif StructKeyExists(rc, EventName)
			  AND (arguments.route EQ "/index.cfm" or arguments.route eq "")
			  AND (
			  		rc[EventName] NEQ DefaultEvent
			  		OR
			  		( structKeyExists(url,EventName) AND rc[EventName] EQ DefaultEvent )
			  )>
			
			<!--- New Pathing Calculations if not the default event. If default, relocate to the domain. --->
			<cfif rc[EventName] neq getSetting('DefaultEvent')>
				<!--- Clean for handler & Action --->
				<cfif StructKeyExists(rc, EventName)>
					<cfset handler = reReplace(rc[EventName],"\.[^.]*$","") />
					<cfset action = ListLast( rc[EventName], "." ) />
				</cfif>
				<!--- route a handler --->
				<cfif len(handler)>
					<cfset newpath = "/" & handler />
				</cfif>
				<!--- route path with handler + action if not the default event action --->
				<cfif len(handler) 
					  AND len(action) 
					  AND action NEQ getDefaultFrameworkAction()>
					<cfset newpath = newpath & "/" & action />
				</cfif>
			</cfif>
			<!--- Debug Mode? --->
			<cfif getDebugMode()>
				<cfset getPlugin("Logger").debug("SES.Invalid URL detected. Route: #arguments.route#, script_name: #arguments.script_name#")>
			</cfif>
			
			<!--- Relocation headers --->
			<cfif httpRequestData.method EQ "GET">
				<cfheader statuscode="301" statustext="Moved permanently" />
			<cfelse>
				<cfheader statuscode="303" statustext="See Other" />
			</cfif>
			<!--- Relocate --->
			<cfheader name="Location" value="#getBaseURL()##newpath##serializeURL(httpRequestData.content,event)#" />
			<cfabort />			
		</cfif>
	</cffunction>
	
	<!--- Fix Ending IIS funkyness --->
	<cffunction name="fixIISURLVars" access="private" returntype="string" hint="Clean up some IIS funkyness" output="false" >
		<cfargument name="requestString"  type="any" required="true" hint="The request string">
		<cfargument name="rc"  			  type="any" required="true" hint="The request collection">
		<cfscript>
			var varMatch = 0;
			var qsValues = 0;
			var qsVal = 0;
			var x = 1;
			
			if ( arguments.requestString CONTAINS "?" ){
				/* Match the positioning of the ? */
				varMatch = REFind("\?.*=", arguments.requestString, 1, "TRUE");
				/* Now copy values to the RC */
				qsValues = REreplacenocase(arguments.requestString,"^.*\?","","all");
				/* loop and create */
				for(x=1; x lte listLen(qsValues,"&"); x=x+1){
					qsVal = listGetAt(qsValues,x,"&");
					rc[listFirst(qsVal,"=")] = listLast(qsVal,"=");
				}
				
				/* Clean the request string */
				arguments.requestString = Mid(arguments.requestString, 1, (varMatch.pos[1]-1));
			}
			
			return arguments.requestString;
		</cfscript>
	</cffunction>
	
	<!--- Find a route --->
	<cffunction name="findRoute" access="private" output="false" returntype="Struct" hint="Figures out which route matches this request">
		<!--- ************************************************************* --->
		<cfargument name="action" required="true" type="any" hint="The action evaluated by the path_info">
		<cfargument name="event"  required="true" type="any" hint="The event object.">
		<!--- ************************************************************* --->
		<cfset var requestString = arguments.action />
		<cfset var packagedRequestString = "">
		<cfset var match = structNew() />
		<cfset var foundRoute = structNew() />
		<cfset var params = structNew() />
		<cfset var key = "" />
		<cfset var i = 1 />
		<cfset var x = 1 >
		<cfset var rc = event.getCollection()>
		<cfset var _routes = getRoutes()>
		<cfset var _routesLength = ArrayLen(_routes)>
		
		<cfscript>
			/* fix URL vars after ? */
			requestString = fixIISURLVars(requestString,rc);
			/* Remove the leading slash */
			if( len(requestString) GT 1 AND left(requestString,1) eq "/" ){
				requestString = right(requestString,len(requestString)-1);
			}
			/* Add ending slash */
			if( right(requestString,1) IS NOT "/" ){
				requestString = requestString & "/";
			}
			
			/* Let's Find a Route, Loop over all the routes array */
			for(i=1; i lte _routesLength; i=i+1){
				/* Match The route to request String */
				match = reFindNoCase(_routes[i].regexPattern,requestString,1,true);
				if( (match.len[1] IS NOT 0 AND getProperty('looseMatching')) OR
				    (NOT getProperty('looseMatching') AND match.len[1] IS NOT 0 AND match.pos[1] EQ 1) ){
					/* Setup the found Route */
					foundRoute = _routes[i];
					/* Debug mode? */
					if( getDebugMode() ){
						getPlugin("Logger").debug("SES.Route matched: #foundRoute.toString()#");					
					}
					break;
				}				
			}//end finding routes
			
			/* Check if we found a route, else just return empty params struct */
			if( structIsEmpty(foundRoute) ){ return params; }
			
			/* Do we need to do package resolving */			
			if( NOT foundRoute.packageResolverExempt ){
				/* Resolve the packages */
				packagedRequestString = packageResolver(requestString,foundRoute.patternParams);
				/* reset pattern matching, if packages found. */
				if( compare(packagedRequestString,requestString) NEQ 0 ){
					if( getDebugMode() ){
						getPlugin("Logger").debug("SES.Package Resolved: #packagedRequestString#");					
					}
					return findRoute(packagedRequestString,arguments.event);
				}
			}
			
			/* Populate the params, with variables found in the request string */
			for(x=1; x lte arrayLen(foundRoute.patternParams); x=x+1){
				params[foundRoute.patternParams[x]] = mid(requestString, match.pos[x+1], match.len[x+1]);
			}
			
			/* Process Convention Name-Value Pairs */
			findConventionNameValuePairs(requestString,match,params);
			
			/* Now setup all found variables in the param struct, so we can return */
			for(key in foundRoute){
				if( NOT listFindNoCase(instance.RESERVED_ROUTE_ARGUMENTS,key) ){
					params[key] = foundRoute[key];
				}
				else if (key eq "matchVariables"){
					for(i=1; i lte listLen(foundRoute.matchVariables); i = i+1){
						params[listFirst(listGetAt(foundRoute.matchVariables,i),"=")] = listLast(listGetAt(foundRoute.matchVariables,i),"=");
					}
				}
			}
			
			/* return params found */
			return params;			
		</cfscript>
	</cffunction>
	
	<cffunction name="findConventionNameValuePairs" access="private" returntype="void" hint="Find the convention name value pairs" output="false" >
		<cfargument name="requestString"  	type="string" 	required="true" hint="The request string">
		<cfargument name="match"  			type="any" 		required="true" hint="The regex matcher">
		<cfargument name="params"  		 	type="struct" 	required="true" hint="The parameter structure">
		<cfscript>
		var leftOverLen = len(arguments.requestString)-(arguments.match.pos[arraylen(arguments.match.pos)]+arguments.match.len[arrayLen(arguments.match.len)]-1);
		var conventionString = 0;
		var conventionStringLen = 0;
		var tmpVar = 0;
		var i = 1;
		
		if( leftOverLen gt 0 ){
			/* Cleanup remianing string */
			conventionString = right(arguments.requestString,leftOverLen);
			conventionStringLen = listLen(conventionString,"/");
			/* If conventions found, continue parsing */
			if( conventionStringLen gt 1 ){
				for(i=1; i lte conventionStringLen; i=i+1){
					if( i mod 2 eq 0 ){
						/* Even: Means Variable Value */
						arguments.params[tmpVar] = listGetAt(conventionString,i,'/');
					}
					else{
						/* ODD: Means variable name */
						tmpVar = trim(listGetAt(conventionString,i,'/'));
						/* Verify it is a valid variable Name */
						if ( NOT isValid("variableName",tmpVar) ){
							tmpVar = "_INVALID_VARIABLE_NAME_POS_#i#_";
						}
						else{
							/* Default Value of empty */
							arguments.params[tmpVar] = "";
						}
					}
				}//end loop over pairs
			}//end if at least one pair found
		}//end if convention name value pairs
		</cfscript>
	</cffunction>
	
	<cffunction name="getCleanedPaths" access="private" returntype="struct" hint="Get and Clean the path_info and script names" output="false" >
		<cfscript>
			var items = structnew();
			
			/* Get path_info */
			items["pathInfo"] = getCGIElement('path_info');
			items["scriptName"] = trim(reReplacenocase(getCGIElement('script_name'),"[/\\]index\.cfm",""));
			
			/* Clean ContextRoots */
			if( len(getContextRoot()) ){
				items["pathInfo"] = replacenocase(items["pathInfo"],getContextRoot(),"");
				items["scriptName"] = replacenocase(items["scriptName"],getContextRoot(),"");
			}	
			/* Clean up the path_info from index.cfm and nested pathing */
			items["pathInfo"] = trim(reReplacenocase(items["pathInfo"],"[/\\]index\.cfm",""));
			/* Clean up empty placeholders */
			items["pathInfo"] = replace(items["pathInfo"],"//","/","all");
			if( len(items["scriptName"]) ){
				items["pathInfo"] = replaceNocase(items["pathInfo"],items["scriptName"],'');
			}
			
			return items;
		</cfscript>
	</cffunction>
	
	<cffunction name="processRouteOptionals" access="private" returntype="void" hint="Process route optionals" output="false" >
		<cfargument name="thisRoute"  type="struct" required="true" hint="The route struct">
		<cfscript>
			var x=1;
			var thisPattern = 0;
			var base = "";
			var optionals = "";
			var routeList = "";
			
			/* Parse our base & optionals */
			for(x=1; x lte listLen(arguments.thisRoute.pattern,"/"); x=x+1){
				thisPattern = listgetAt(arguments.thisRoute.pattern,x,"/");
				/* Check for ? */
				if( not findnocase("?",thisPattern) ){ 
					base = base & thisPattern & "/"; 
				}
				else{ 
					optionals = optionals & replacenocase(thisPattern,"?","","all") & "/";
				}
			}
			/* Register our routeList */
			routeList = base & optionals;
			/* Recurse and register in reverse order */
			for(x=1; x lte listLen(optionals,"/"); x=x+1){
				/* Create new route */
				arguments.thisRoute.pattern = routeList;
				/* Register route */
				addRoute(argumentCollection=arguments.thisRoute);	
				/* Remove last bit */
				routeList = listDeleteat(routeList,listlen(routeList,"/"),"/");		
			}
			/* Setup the base route again */
			arguments.thisRoute.pattern = base;
			/* Register the final route */
			addRoute(argumentCollection=arguments.thisRoute);
		</cfscript>
	</cffunction>

</cfcomponent>