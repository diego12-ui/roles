# Azure Role Assignment Script
# Requiere: Az PowerShell Module

$rolesRestringidos = @(
   "Owner",
   "Contributor",
   "User Access Administrator",
   "Reservations Administrator",
   "Access Review Operator Service Role",
   "Role Based Access Control Administrator",
   "Service Group Contributor",
   "Administrador IBM Cloud",
   "Environment Automation",
   "Environment Automation II",
   "Rol Administrador de Accesos",
   "Rol Administrador de Accesos PIM",
   "Administrador Modelo Soporte",
   "Environment Operator APIM",
   "Rol Modificar NSG SOAR",
   "Rol Networking Whitelist - Ambientes Previos"
   "Developer Environment Operator"
   "Environment Operator"
   "Reader Environment Certi"
   "Reader Certi QA"
)

# Función para mostrar menú
function Show-Menu {
    param([string]$Title, [array]$Options)
    
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "$($i + 1). $($Options[$i])" -ForegroundColor Yellow
    }
    
    do {
        $selection = Read-Host "`nSelecciona una opción (1-$($Options.Length))"
        $index = [int]$selection - 1
    } while ($index -lt 0 -or $index -ge $Options.Length)
    
    return $Options[$index]
}

# Función principal
function New-AzureRoleAssignment {
    Write-Host "=== AZURE ROLE ASSIGNMENT TOOL ===" -ForegroundColor Green
    
    # Verificar conexión a Azure
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "No estás conectado a Azure. Ejecutando Connect-AzAccount..." -ForegroundColor Yellow
            Connect-AzAccount
        }
        Write-Host "Conectado a Azure - Tenant: $($context.Tenant.Id)" -ForegroundColor Green
    }
    catch {
        Write-Error "Error al conectar con Azure: $($_.Exception.Message)"
        return
    }
    
    # 1. Seleccionar tipo de principal
    $principalTypes = @("Security Group", "Service Principal", "Managed Identity", "User")
    $selectedPrincipalType = Show-Menu -Title "Tipo de Principal" -Options $principalTypes
    
    # 2. Obtener nombre del principal
    $principalName = Read-Host "`nIngresa el nombre del $selectedPrincipalType"
    
    # 3. Seleccionar ámbito
    $scopes = @("Management Group", "Subscription", "Resource Group", "Resource")
    $selectedScope = Show-Menu -Title "Ámbito de Asignación" -Options $scopes
    
    # Variables para construir el scope
    $scopePath = ""
    $roleName = ""

    # GLOBALES
    $codapp = Read-Host "Nombre de la aplicacion"
    $grupodered = Read-Host "Nombre de grupo de red"
    $ambienteToSelect = @("Desarrollo", "Certificación", "Producción")
    $ambiente = Show-Menu -Title "Seleccionar ambientes" -Options $ambienteToSelect

    # NOSE SI ESTO VA O NO
    #Write-Host "Iniciando sesión en Azure con Managed Identity..."
    #Connect-AzAccount -Identity
    
    # 4. Configurar según el ámbito seleccionado
    switch ($selectedScope) {
        "Management Group" {
            $mgName = Read-Host "`nNombre del Management Group"
            $roleName = Read-Host "Nombre del Rol"
            $scopePath = "/providers/Microsoft.Management/managementGroups/$mgName"

            # VALIDAR SI EXISTE MG
            if (-not $mgName) {
                throw "No se encontró el Nombre del Management Group."
            }

            # VALIDAR QUE EL AMBIENTE SEA PRODUCCION
            if ($ambiente -ne "Producción") {
                throw "El ambiente debe ser productivo para este tipo de solicitud."
            }

            # VALIDAR SI EXISTE EL GRUPO DE RED
            Write-Host "Validando si existe el Grupo de Red"
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) {
               throw "El grupo de red '$grupodered' no existe en Azure AD."
            }

            # VALIDAR QUE EL GRUPO CORRESPONDA A POAZ
            Write-Host "Validar que el grupo corresponda a 'POAZ'."
            if ($grupodered -notlike 'POAZ_*') {
                throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ', favor de ingresar un grupo 'POAZ' valido." 
            }

            # VALIDAR QUE EL GRUPO CORRESPONDA A POAZ CROSS
            Write-Host "Validar que el grupo corresponda a 'POAZ CROSS'."
            if ($grupodered -notlike 'POAZ_SOPORTE_*' -and $grupodered -notlike 'POAZ_OPERATOR_*'-and $grupodered -notlike 'POAZ_READER_*' -and $grupodered -notlike 'POAZ_NET_*') {
                throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ' cross, favor de ingresar un grupo 'POAZ' valido." 
            }

            # VALIDAR QUE EL GRUPO CORRESPONDA A PROD
            Write-Host "Validar que el grupo corresponda a 'PROD'."
            if ($grupodered -notlike '*_PROD') {
                throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ PROD' cross, favor de ingresar un grupo 'POAZ' valido." 
            }

            # VALIDACIÓN DE ROLES RESTRINGIDOS
            Write-Host "Validando si el rol esta restringido"

            if ($rolesRestringidos -contains $roleName) {
               throw "El Rol '$roleName' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }
            
            # VALIDAR SI EL GRUPO DE RED YA CUENTA CON EL ROL
            $idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id
            $rol= $Request.body.rol

            Write-Host "Verificando si el grupo de red ya cuenta con el rol en el Management Group"

            $assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope "/providers/Microsoft.Management/managementGroups/$mg"
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $rol }
            if ($Assigned) {
               Write-Host "El Grupo de Red '$idgrupodered' ya tiene el rol '$rol' asignado a nivel de Management Group."
            }

        }
        
        "Subscription" {
            $subscriptionName = Read-Host "`nNombre de la Suscripción"
            $roleName = Read-Host "Nombre del Rol"
            
            # Obtener subscription ID
            $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
            if (-not $subscription) {
                Write-Error "Suscripción '$subscriptionName' no encontrada"
                return
            }
            $scopePath = "/subscriptions/$($subscription.Id)"

            # VALIDAR SI ES AMBIENTE PRODUCTIVO
            if ($ambiente -ne "Producción") {
                throw "El ambiente debe ser productivo para este tipo de solicitud."
            }

            # VALIDAR QUE LA SUSCRIPCION CORRESPONDA CON EL CODIGO DE APP
            Write-Host "Validando que la suscripcion corresponda al codigo de aplicación"
            if ($suscripcion -notlike "*$codapp*") {
               throw "El codigo de aplicación '$codapp' no corresponde a la suscripción '$suscripcion'."
            }
            # VALIDACION DE SUSCRIPCIONES NO PERMITIDAS
            $noPermitidas = @(
                "DTI - INF - INFR - Servicios Compartidos",
                "Azure EA - Credicorp"
            )

            Write-Host "Validación de suscripciones no permitidas"
            if ($noPermitidas -contains $suscripcion) {
                throw "La solicitud no será atendida, no esta permitida la asinación de roles para la suscripción '$suscripcion'."
            }

            # VALIDAR SI EXISTE GRUPO DE RED
            $IdSuscripcion = (Get-AzSubscription -SubscriptionName $suscripcion).id
            Set-AzContext -Subscription $IdSuscripcion -Force

            Write-Host "Validando si existe el Grupo de Red"
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) {
               throw "El grupo de red '$grupodered' no existe en Azure AD."
            }

            # VALIDACION DE NOMBRES VALIDOS
            $costGroup = "POAZ_COSTMANAGEMENT_$codapp"
            $dashGroup = "POAZ_DASHBOARD_$codapp"

            Write-Host "Validando rol permitido"
            if ($roleName -ne "Cost Management Reader" -and $roleName -ne "Dashboard Reader") {
                throw "Rol no válido: '$roleName'. Solo se permiten 'Cost Management Reader' o 'Dashboard Reader'."
            }

            # VALIDAR GRUPO DE RED PERMITODO
            Write-Host "Validando grupo de red permitido"
            if ($grupodered -ne $costGroup -and $grupodered -ne $dashGroup) {
                throw "Grupo de red no válido: '$grupodered'. Debe ser '$costGroup' o '$dashGroup'."
            }

            Write-Host "Validar consistencia entre grupo de red y rol asignado"
            if ($grupodered -eq $costGroup -and $roleName -ne "Cost Management Reader") {
                throw "Se ingreso el rol '$roleName' de manera incorrecta, el grupo '$grupodered' requiere el rol 'Cost Management Reader'."
            }
            elseif ($grupodered -eq $dashGroup -and $roleName -ne "Dashboard Reader") {
                throw "Se ingreso el rol '$roleName' de manera incorrecta, El grupo '$grupodered' requiere el rol 'Dashboard Reader'."
            }

            # VALIDACIÓN DE ROLES RESTRINGIDOS
            Write-Host "Validando si el rol esta restringido"

            if ($rolesRestringidos -contains $roleName) {
               throw "El Rol '$roleName' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }

            # VALIDAR ROL A NIVEL DE SUSCRIPCION
            Write-Host "validar si el rol existe a nivel de suscripçion"

            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if ($role) {
              Write-Host "El rol '$rol' está disponible para la suscripción '$suscripcion'."
            }else {
               throw "El rol '$rol' NO está disponible para la suscripción '$suscripcion'."
            }

            # VALIDAR SI SUS YA CUENTA CON GRUPO DE RED
            Write-Host "Verificando si el Grupo de Red ya cuenta con el rol en la suscripcion"

            $idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id
            $assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope "/subscriptions/$IdSuscripcion"
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $rolName }
            if ($Assigned) {
               Write-Host "El grupo '$grupodered' ya tiene el rol '$rolName' asignado a nivel de suscripción."
            }
        }
        
        "Resource Group" {
            $subscriptionName = Read-Host "`nNombre de la Suscripción"
            $rgName = Read-Host "Nombre del Resource Group"
            $roleName = Read-Host "Nombre del Rol"

            if (-not $suscripcion) {
                throw "No se encontró el Nombre de la Suscripcion."
            }
            if (-not $rg) {
                throw "No se encontró el Nombre del Grupo de Recursos."
            }
            
            # Obtener subscription ID
            $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
            if (-not $subscription) {
                Write-Error "Suscripción '$subscriptionName' no encontrada"
                return
            }
            $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$rgName"

            # VALIDAR QUE EL RG EXISTA EN AZURE
            $resourceGroupName = Get-AzResourceGroup -Name $rgName-ErrorAction SilentlyContinue
            if ($null -eq $resourceGroupName) {
               throw  "El grupo de recursos '$rg' NO existe."
            }

            # VALIDAR TAG
            if (-not $resourceGroupName.Tags.ContainsKey("environment")) {
                throw "El grupo de recursos '$rg' no cuenta con un ambiente definido."
            }

            $tagValue = $resourceGroupName.Tags["environment"].ToLower()

            Write-Host "Determinar ambiente esperado según el tag"

            switch ($tagValue) {
                "prod" { $ambienteEsperado = "Producción" }
                "desa" { $ambienteEsperado = "Desarrollo" }
                "cert" { $ambienteEsperado = "Certificación" }
                default {
                    throw "El grupo de recursos '$rg' no cuenta con un ambiente definido."
                }
            }
            if ($ambienteEsperado -ne $ambiente) {
                throw "El grupo de recursos '$rg' no corresponde al ambiente seleccionado '$ambiente'."
            }
            
            $grupoDev = "POAZ_DEV_${codapp}_DESA"
            $grupoLTDev  = "POAZ_LT_${codapp}_DESA"
            $grupoLTcert = "POAZ_LT_${codapp}_CERT"
            $grupoQAcert = "POAZ_QA_${codapp}_CERT"

            $roldev = "Developer Environment Operator"
            $roldevlt = "Environment Operator"
            $rolcertlt = "Reader Environment Certi"
            $rolcertqa = "Reader Certi QA"

            # VALIDAR QUE EL GRUPO CORRESPONDA A POAZ
            Write-Host "Validar que el grupo corresponda a 'POAZ'."
            if ($grupodered -notmatch "POAZ") {
                throw "El grupo '$grupodered' no contiene 'POAZ' en su nombre, favor de ingresar un grupo 'POAZ' valido." 
            }

            # VALIDAR QUE EL GRUPO TENGA EL CODIGO DE APLICACION
            Write-Host "Validar que el grupo contenga el código de aplicación"
            if ($grupodered -notmatch $codapp) {
                throw "El grupo '$grupodered' no corresponde al '$codapp'."
            }

            # VALIDACION DE ROLES
            Write-Host "Validando que los roles estandard pertenece al ambiente desarrollo"
            if ($roleName -eq $roldev -or $roleName -eq $roldevlt) {
                if ($ambiente -ne "desarrollo") {
                    throw "El rol '$roleName' no corresponde al ambiente de '$ambiente'." 
                } else {
                    Write-Host "El grupo '$roleName' corresponde al ambiente de desarrollo."
                }
            } 

            Write-Host "Validando que los roles estandard pertenece al ambiente certificación"
            if ($roleName -eq $rolcertlt -or $roleName -eq $rolcertqa) {
                if ($ambiente -ne "certificación") {
                    throw "El rol '$roleName' no corresponde al ambiente de '$ambiente'." 
                } else {
                    Write-Host "El rol '$roleName' corresponde al ambiente de certificación."
                }
            }

            # VALIDACION DE GRUPOS DE RED
            Write-Host "Validando si existe el Grupo de Red"
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) {
               throw "El grupo de red '$grupodered' no existe en Azure AD."
            }

            Write-Host "Validando grupos de red poaz estandard pertenece al ambiente desarrollo"
            if ($grupodered -eq $grupoDev -or $grupodered -eq $grupoLTDev) {
                if ($ambiente -ne "desarrollo") {
                    throw "El grupo '$grupodered' no corresponde al ambiente de '$ambiente'." 
                } else {
                    Write-Host "El grupo '$grupodered' corresponde al ambiente de desarrollo."
                }
            } 

            Write-Host "Validando grupos de red poaz estandard pertenece al ambiente certificación"
            if ($grupodered -eq $grupoQAcert -or $grupodered -eq $grupoLTcert) {
                if ($ambiente -ne "certificación") {
                    throw "El grupo '$grupodered' no corresponde al ambiente de '$ambiente'." 
                } else {
                    Write-Host "El grupo '$grupodered' corresponde al ambiente de certificación."
                }
            } 


            Write-Host "Validando grupos de red poaz estandard con los roles respectivos"
            if ($ambiente -eq "Desarrollo") {
                switch ($roleName) {
                    "Developer Environment Operator" {
                        if ($grupodered -eq $grupoDev) {
                            Write-Host "Rol válido para grupo $grupodered en ambiente desarrollo."
                        } else {
                            throw "Rol 'Developer Environment Operator' solo es válido para el grupo            $grupoDev."
                        }
                    }
                    "Environment Operator" {
                        if ($grupodered -eq $grupoLTDev) {
                            Write-Host "Rol válido para grupo $grupodered en ambiente desarrollo."
                        } else {
                            throw "Rol 'Environment Operator' solo es válido para el grupo $grupoLTDev."
                        }
                    }default {
                        throw "Rol inválido para ambiente desarrollo. Solo se permiten: 'Developer          Environment Operator' o 'Environment Operator'."
                    }
                }
            }

            Write-Host "Validando grupos de red poaz estandard con los roles respectivos"
            if ($ambiente -eq "Certificación") {
                switch ($roleName) {
                    "Reader Certi QA" {
                        if ($grupodered -eq $grupoQAcert ) {
                            Write-Host "Rol válido para grupo $grupodered en ambiente certificación."
                        } else {
                            throw "Rol 'Reader Certi QA' solo es válido para el grupo $grupoQAcert."
                        }
                    }
                    "Reader Environment Certi" {
                        if ($grupodered -eq $grupoLTcert) {
                            Write-Host "Rol válido para grupo $grupodered en ambiente desarrollo."
                        } else {
                            throw "Rol 'Reader Environment Certi' solo es válido para el grupo $grupoLTcert.            "
                        }
                    }default {
                        throw "Rol inválido para ambiente certificación. Solo se permiten: 'Reader Certi            QA' o 'Reader Environment Certi'."
                    }
                }
            }

            Write-Host "Validar si el grupo termina con prod_poaz, cert_poaz o desa_poaz"
            if (
                $grupodered -notlike '*_prod_poaz' -and
                $grupodered -notlike '*_cert_poaz' -and
                $grupodered -notlike '*_desa_poaz'
            ) {
                throw "El grupo '$grupodered' no es un grupo 'POAZ' adicional de aplicación, favor de           ingresar un grupo 'POAZ' valido."
            }

            Write-Host "Validar que el grupo coincida con el ambiente según sufijo"
            switch ($true) {
                { $grupodered -like '*_prod_poaz' -and $ambiente -ne 'Producción' } {
                    throw "El grupo es productivo, pero el ambiente no es 'producción'."
                }
                { $grupodered -like '*_cert_poaz' -and $ambiente -ne 'Certificación' } {
                    throw "El grupo es de certificación, pero el ambiente no es 'certificación'."
                }
                { $grupodered -like '*_desa_poaz' -and $ambiente -ne 'Desarrollo' } {
                    throw "El grupo es de desarrollo, pero el ambiente no es 'desarrollo'."
                }
                default {
                    Write-Host "El grupo '$grupodered' corresponde al ambiente '$ambiente'."
                }
            }

            # VALIDACIÓN DE ROLES RESTRINGIDOS
            Write-Host "Validando si el rol esta restringido"

            if ($rolesRestringidos -contains $roleName) {
               throw "El Rol '$roleName' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }

            # VALIDAR SI EL ROL EXISTE A NIVEL DE SUSCRIPCION
            Write-Host "validar si el rol existe a nivel de suscripçion"

            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            # Verificar si la suscripción está en los ámbitos asignables
            if ($role) {
              Write-Host "El rol '$roleName' está disponible para la suscripción '$suscripcion'."
            }else {
               throw "El rol '$roleName' NO está disponible para la suscripción '$suscripcion'."
            }

            # VALIDAR SI EL ROL EXISTE A NIVEL DE RG
            Write-Host "Verificando si el Grupo de Red ya cuenta con el rol en el resource group"

            $asignacion = Get-AzRoleAssignment -ObjectId $idgrupodered -ResourceGroupName $rgName -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $roleName}
            if ($null -ne $asignacion) {
               Write-Host "El rol '$roleName' ya está asignado al grupo de red '$grupodered' en el Resource Group '$rgName'."
            }
        }
        
        "Resource" {
            $subscriptionName = Read-Host "`nNombre de la Suscripción"
            $rgName = Read-Host "Nombre del Resource Group"
            $resourceType = Read-Host "Tipo de Recurso (ej: Microsoft.Storage/storageAccounts)"
            $resourceName = Read-Host "Nombre del Recurso"
            $roleName = Read-Host "Nombre del Rol"

            # ========= PARA SP SOLO FALTARIAN LAS VALIDACIONES RELACIONADAS A SP =========
            
            # Obtener subscription ID
            $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
            if (-not $subscription) {
                Write-Error "Suscripción '$subscriptionName' no encontrada"
                return
            }
            $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$rgName/providers/$resourceType/$resourceName"

            # VALIDACION DE CODIGO DE APLICACIÓN
            Write-Host "Validando codigo de aplicación"
            if ($rgName -like "*$codapp*") {
                Write-Host "El codigo de aplicación '$codapp' corresponde al grupo de recursos '$rgName'."
            }else{
                throw "El codigo de aplicación '$codapp' no corresponde al grupo de recursos '$rgName'."
            }

            # VALIDARCION DE RG
            $resourceGroupName = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
            # Validar si existe
            if ($null -eq $resourceGroupName) {
               throw  "El grupo de recursos '$rgName' NO existe."
            }

            # VALIDACION QUE EXISTA GRUPO DE RED
            Write-Host "Validando si existe el Grupo de Red"
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) {
               throw "El grupo de red '$grupodered' no existe en Azure AD."
            }

            # VALIDACON SI EXISTE RESOURCE
            $resource = Get-AzResource -Name $recurso -ResourceGroupName $rgName -ErrorAction SilentlyContinue
            if(-not $resource){
                throw "El recurso '$recurso' no existe en el grupo de recursos '$rgName'."
            }

            # VALIDACION QUE EL GRUPO CONTENGA EL CODIGO DE APLICACION
            Write-Host "Validar que el grupo contenga el código de aplicación"
            if ($grupodered -notmatch $codapp) {
                throw "El grupo '$grupodered' no corresponde al '$codapp'."
            }

            Write-Host "Validando si el grupo de red esta restringido"
            $grRestringidos = @(
               "POAZ_DEV_${codapp}_DESA"
               "POAZ_LT_${codapp}_DESA"
               "POAZ_LT_${codapp}_CERT"
               "POAZ_QA_${codapp}_CERT"
            )

            if ($grRestringidos -contains $grupodered) {
               throw "El grupo de red '$grupodered' no esta permitido para este tipo de solicitud"
            }

            # VALIDACION DE NOMBRE GRUPO
            Write-Host "Validar si el grupo termina con prod_poaz, cert_poaz o desa_poaz"
            if (
                $grupodered -notlike '*_prod_poaz' -and
                $grupodered -notlike '*_cert_poaz' -and
                $grupodered -notlike '*_desa_poaz'
            ) {
                throw "El grupo '$grupodered' no es un grupo 'POAZ' adicional de aplicación, favor de ingresar un grupo 'POAZ' valido."
            }

            #VALIDACION DE AMBIENTE DE GRUPO
            Write-Host "Validar que el grupo coincida con el ambiente según sufijo"
            switch ($true) {
                { $grupodered -like '*_prod_poaz' -and $ambiente -ne 'Producción' } {
                    throw "El grupo es productivo, pero el ambiente no es 'producción'."
                }
                { $grupodered -like '*_cert_poaz' -and $ambiente -ne 'Certificación' } {
                    throw "El grupo es de certificación, pero el ambiente no es 'certificación'."
                }
                { $grupodered -like '*_desa_poaz' -and $ambiente -ne 'Desarrollo' } {
                    throw "El grupo es de desarrollo, pero el ambiente no es 'desarrollo'."
                }
                default {
                    Write-Host "El grupo '$grupodered' corresponde al ambiente '$ambiente'."
                }
            }

            # VALIDACIÓN DE ROLES RESTRINGIDOS
            Write-Host "Validando si el rol esta restringido"

            if ($rolesRestringidos -contains $roleName) {
               throw "El Rol '$roleName' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }

            # VALIDAR SI EL ROL EXISTE A NIVEL DE SUS
            Write-Host "validar si el rol existe a nivel de suscripçion"

            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            # Verificar si la suscripción está en los ámbitos asignables
            if ($role) {
              Write-Host "El rol '$roleName' está disponible para la suscripción '$suscripcion'."
            } else {
               throw "El rol '$roleName' NO está disponible para la suscripción '$suscripcion'."
            }

            # VALIDAR SI YA EXISTE ASIGNACION
            $idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id
            $idresource = Get-AzResource -ResourceGroupName $rgName -Name $recurso
            $idrecurso = $idresource.ResourceId
            $tiporecurso = $Request.Body.tiporecurso
            $asignacion = Get-AzRoleAssignment -Scope $idrecurso -ObjectId $idgrupodered -ErrorAction SilentlyContinue | Where-Object {
               $_.RoleDefinitionName -eq $roleName
            }
            if ($null -ne $asignacion) {
               Write-Host "Ya existe una asignación del rol '$roleName' para el grupo de red '$grupodered'."
            }

            $azureServices = @{
                "API Management"               = "Microsoft.ApiManagement/service"
                "App Service plan"            = "Microsoft.Web/serverfarms"
                "Application gateway"         = "Microsoft.Network/applicationGateways"
                "Application Insights"        = "Microsoft.Insights/components"
                "Azure Function"              = "Microsoft.Web/sites"
                "Automation Account"          = "Microsoft.Automation/automationAccounts"
                "Container registry"          = "Microsoft.ContainerRegistry/registries"
                "Azure Data Explorer Cluster" = "Microsoft.Kusto/Clusters"
                "Azure Databricks"            = "Microsoft.Databricks/workspaces"
                "DNS zone"                    = "Microsoft.Network/dnszones"
                "Event Hub"                   = "Microsoft.EventHub/namespaces"
                "Event Grid Topic"            = "Microsoft.EventGrid/topics"
                "Event Grid System Topic"     = "Microsoft.EventGrid/systemTopics"
                "Front Door and CDN profile"  = "Microsoft.Cdn/profiles"
                "Kubernetes service"          = "Microsoft.ContainerService/managedClusters"
                "Key vault"                   = "Microsoft.KeyVault/vaults"
                "Storage account"             = "Microsoft.Storage/storageAccounts"
                "SQL server"                  = "Microsoft.Sql/servers"
                "Azure Cosmos DB"             = "Microsoft.DocumentDB/databaseAccounts"
                "Azure Cache for Redis"       = "Microsoft.Cache/Redis"
                "Web App"                     = "Microsoft.Web/sites"
                "Virtual network"             = "Microsoft.Network/virtualNetworks"
                "Data factory"                = "Microsoft.DataFactory/factories"
                "Log Analytics"               = "Microsoft.OperationalInsights/workspaces"
                "Logic app"                   = "Microsoft.Logic/workflows"
                "Virtual machine"             = "Microsoft.Compute/virtualMachines"
                "Azure Bot"                   = "Microsoft.BotService/botServices"
            }

            # Validar si existe
            if ($azureServices.ContainsKey($tiporecurso)) {
                $resourceType = $azureServices[$tiporecurso]
                Write-Host "Resource Type de '$tiporecurso' es: $resourceType"
            }
        }
    }
    
    # 5. Tipo de asignación
    $assignmentTypes = @("Permanente", "Temporal")
    $selectedAssignmentType = Show-Menu -Title "Tipo de Asignación" -Options $assignmentTypes
    
    # Variables para asignación temporal
    $startTime = $null
    $endTime = $null
    
    if ($selectedAssignmentType -eq "Temporal") {
        Write-Host "`n--- Configuración de Asignación Temporal ---" -ForegroundColor Cyan
        $startTimeInput = Read-Host "Fecha/Hora de inicio (formato: yyyy-MM-dd HH:mm) [Enter para ahora]"
        $endTimeInput = Read-Host "Fecha/Hora de fin (formato: yyyy-MM-dd HH:mm)"
        
        if ([string]::IsNullOrWhiteSpace($startTimeInput)) {
            $startTime = Get-Date
        } else {
            $startTime = [DateTime]::ParseExact($startTimeInput, "yyyy-MM-dd HH:mm", $null)
        }
        
        $endTime = [DateTime]::ParseExact($endTimeInput, "yyyy-MM-dd HH:mm", $null)
    }
    
    # 6. Obtener el principal ID
    Write-Host "`nBuscando principal '$principalName'..." -ForegroundColor Yellow
    $principalId = $null
    
    try {
        switch ($selectedPrincipalType) {
            "Security Group" {
                $group = Get-AzADGroup -DisplayName $principalName -ErrorAction SilentlyContinue
                if ($group) { $principalId = $group.Id }
            }
            "Service Principal" {
                $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
                if ($sp) { $principalId = $sp.Id }
            }
            "Managed Identity" {
                $mi = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
                if ($mi) { $principalId = $mi.Id }
            }
            "User" {
                $user = Get-AzADUser -DisplayName $principalName -ErrorAction SilentlyContinue
                if (-not $user) {
                    $user = Get-AzADUser -UserPrincipalName $principalName -ErrorAction SilentlyContinue
                }
                if ($user) { $principalId = $user.Id }
            }
        }
        
        if (-not $principalId) {
            Write-Error "No se encontró el principal '$principalName' del tipo '$selectedPrincipalType'"
            return
        }
        
        Write-Host "Principal encontrado: ID = $principalId" -ForegroundColor Green
        
    } catch {
        Write-Error "Error al buscar el principal: $($_.Exception.Message)"
        return
    }
    
    # 7. Mostrar resumen y confirmar
    Write-Host "`n=== RESUMEN DE ASIGNACIÓN ===" -ForegroundColor Magenta
    Write-Host "Principal: $principalName ($selectedPrincipalType)" -ForegroundColor White
    Write-Host "Rol: $roleName" -ForegroundColor White
    Write-Host "Ámbito: $selectedScope" -ForegroundColor White
    Write-Host "Scope Path: $scopePath" -ForegroundColor White
    Write-Host "Tipo: $selectedAssignmentType" -ForegroundColor White
    
    if ($selectedAssignmentType -eq "Temporal") {
        Write-Host "Inicio: $startTime" -ForegroundColor White
        Write-Host "Fin: $endTime" -ForegroundColor White
    }
    
    $confirm = Read-Host "`n¿Proceder con la asignación? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Operación cancelada." -ForegroundColor Yellow
        return
    }
    
    # 8. Ejecutar asignación
    Write-Host "`nEjecutando asignación de rol..." -ForegroundColor Yellow
    
    try {
        $params = @{
            ObjectId = $principalId
            RoleDefinitionName = $roleName
            Scope = $scopePath
        }
        
        # Agregar parámetros de tiempo si es temporal
        if ($selectedAssignmentType -eq "Temporal") {
            # Nota: Azure PowerShell no soporta directamente asignaciones temporales
            # Se requiere usar PIM (Privileged Identity Management) o REST API
            Write-Warning "Las asignaciones temporales requieren PIM. Creando asignación permanente..."
        }
        
        $assignment = New-AzRoleAssignment @params
        
        Write-Host "`n✅ Asignación de rol completada exitosamente!" -ForegroundColor Green
        Write-Host "Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Cyan
        
    } catch {
        Write-Error "Error al crear la asignación: $($_.Exception.Message)"
        
        # Sugerencias de errores comunes
        if ($_.Exception.Message -like "*does not exist*") {
            Write-Host "`n💡 Sugerencia: Verifica que el nombre del rol sea correcto. Roles comunes:" -ForegroundColor Yellow
            Write-Host "   - Owner" -ForegroundColor Gray
            Write-Host "   - Contributor" -ForegroundColor Gray
            Write-Host "   - Reader" -ForegroundColor Gray
            Write-Host "   - User Access Administrator" -ForegroundColor Gray
        }
    }
}

# Función adicional para listar roles disponibles
function Get-AvailableRoles {
    Write-Host "`n=== ROLES DISPONIBLES ===" -ForegroundColor Cyan
    Get-AzRoleDefinition | Select-Object Name, Description | Sort-Object Name | Format-Table -AutoSize
}

# Ejecutar la función principal
New-AzureRoleAssignment

Write-Host "`n💡 Tip: Ejecuta 'Get-AvailableRoles' para ver todos los roles disponibles" -ForegroundColor Green