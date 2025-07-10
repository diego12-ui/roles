using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$body = ""
$statusCode = [HttpStatusCode]::OK
$codapp= $Request.Body.codapp
$suscripcion = $Request.Body.suscription
$rg = $Request.Body.resourcegroup
$ambiente = $Request.Body.ambiente

try {
    # Validación de campos en el body
    if (-not $suscripcion) {
        throw "No se encontró el Nombre de la Suscripcion."
    }
  if (-not $rg) {
        throw "No se encontró el Nombre del Grupo de Recursos."
    }

Write-Host "Iniciando sesión en Azure con Managed Identity..."
    Connect-AzAccount -Identity


#$suscripcionescompartidas = @(
#    "DTI - INF - INFR - Servicios Compartidos",
#    "Azure EA - Credicorp"
#)

<#Write-Host "Validando suscripciones compartidas"
if ($suscripcionescompartidas -contains $suscripcion) {
    if ($rg -like "*$codapp*") {
        Write-Host "El codigo de aplicación '$codapp' corresponde al grupo de recursos '$rg'."
    }else{
         throw "El codigo de aplicación '$codapp' no corresponde al grupo de recursos '$rg'."
    }
}
#>

Write-Host "Validando codigo de aplicación"
if ($rg -like "*$codapp*") {
        Write-Host "El codigo de aplicación '$codapp' corresponde al grupo de recursos '$rg'."
}else{
         throw "El codigo de aplicación '$codapp' no corresponde al grupo de recursos '$rg'."
}

Write-Host "Validando que la suscripcion exista en Azure"
$IdSuscripcion = (Get-AzSubscription -SubscriptionName $suscripcion).id
if ( -not $IdSuscripcion){
throw "La suscripcion no existe."
}

Set-AzContext -Subscription $IdSuscripcion -Force

Write-Host "Validando que el RG exista en Azure"

# Intentar obtenerlo
$resourceGroupName2 = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
# Validar si existe
if ($null -eq $resourceGroupName2) {
   throw  "El grupo de recursos '$rg' NO existe."
}

$resourceGroupName = Get-AzResourceGroup -Name $rg -ErrorAction Stop
$sp = $Request.Body.sp
Write-Host "Validar si el tag 'environment' existe" 

if (-not $resourceGroupName.Tags.ContainsKey("environment")) {
   throw "El grupo de recursos '$rg' no cuenta con un ambiente definido."
}

Write-Host " Obtener el valor del tag"

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

Write-Host "Comparar con la variable $ambiente"

if ($ambienteEsperado -ne $ambiente) {
   throw "El grupo de recursos '$rg' no corresponde al ambiente seleccionado '$ambiente'."
} 

switch ($ambiente.ToUpper()) {
    "Desarrollo" {
        if ($sp -notmatch "des") {
            throw "El SP '$sp' no corresponde al ambiente 'Desarrollo'."
        }
    }
    "Certificación" {
        if ($sp -notmatch "cer") {
            throw "El SP '$sp' no corresponde al ambiente 'Certificación'."
        }
    }
    "Producción" {
        if ($sp -notmatch "pro") {
            throw "El SP '$sp' no corresponde al ambiente 'Producción'."
        }
    }
    Default {
        throw "Ambiente '$ambiente' no reconocido. Usa Desarrollo, Certificación o Producción."
    }
}

Write-Host "Validando si existe el Service Principal"
$sp2 = Get-AzADServicePrincipal -DisplayName $sp -ErrorAction SilentlyContinue
# Validar si existe

if (-not $sp2) {
   throw "El Service Principal '$sp' no existe en Azure AD."
}

$idsp = (Get-AzADServicePrincipal -DisplayName $sp).id
$rol= $Request.body.rol
Write-Host "Validando si el rol esta restringido"
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
# ejecutando condicion

if ($rolesRestringidos -contains $rol) {
   throw "El Rol '$rol' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
} 


Write-Host "validar si el rol existe a nivel de suscripçion"

$role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $rol}
# Verificar si la suscripción está en los ámbitos asignables
if ($role) {
  Write-Host "El rol '$rol' está disponible para la suscripción '$suscripcion'."
}else {
   throw "El rol '$rol' NO está disponible para la suscripción '$suscripcion'."
}

#validar si el rg ya cuenta con el sp
Write-Host "Verificando si el service principal ya cuenta con el rol en el resource group"

$asignacion = Get-AzRoleAssignment -ObjectId $idsp -ResourceGroupName $rg -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $rol}
# Validar si el rol está asignado
if ($null -ne $asignacion) {
   Write-Host "El rol '$rol' ya está asignado al Service Principal '$sp' en el Resource Group '$rg'."
}

$tipoAsignacion= $Request.body.duracion

if ($tipoAsignacion -eq "Permanente") {

#Asignar rol para la  suscripçion
Write-Host "Asignando rol en el RG"
New-AzRoleAssignment -ObjectId $idsp -RoleDefinitionName $rol -ResourceGroupName $rg

Write-Host "Se agrego el rol '$rol' permanente correspondiente al service principal '$sp' en el grupo de recursos '$rg'"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' Permanente de manera exitosa en el grupo de recursos '$rg'"
}

elseif ($tipoAsignacion -eq "Temporal") {
$horaPeruTextoini = $Request.body.fechainicio
$horaPeruTextofin = $Request.body.fechafin
Write-Host "fecha inicio '$horaPeruTextoini'"
Write-Host "fecha fin '$horaPeruTextofin'"
$horaPeruTextoiniRecortada = $horaPeruTextoini -replace '\.\d{3}-\d{4}$', ''
Write-Host "fecha inicio2 '$horaPeruTextoiniRecortada'"
$horaPeruTextofinRecortada = $horaPeruTextofin -replace '\.\d{3}-\d{4}$', ''
Write-Host "fecha fin2 '$horaPeruTextofinRecortada'"
$horaUTCini = [datetime]::ParseExact($horaPeruTextoiniRecortada, "MM/dd/yyyy HH:mm:ss", $null)
$horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
Write-Host "fecha inicio 3 '$horaUTCini'"
Write-Host "fecha inicio 4 '$horaUTCini2'"
$horaUTCfin = [datetime]::ParseExact($horaPeruTextofinRecortada, "MM/dd/yyyy HH:mm:ss", $null)
$horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
Write-Host "fecha fin 3 '$horaUTCfin'"
Write-Host "fecha fin 4 '$horaUTCfin2'"
# Paso 2: (Opcional) Convertir a hora Perú solo para mostrar/log
$zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
$horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
$horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
Write-Host "Hora Perú inicio: $horaPeruini"
Write-Host "Hora Perú fin: $horaPerufin"

$guid = [guid]::NewGuid().ToString()
$inicio= $horaUTCini2
$fin= $horaUTCfin2
$startTime = Get-Date $inicio -Format o  # Specify your start time here
$endTime = Get-Date $fin -Format o    # Specify your end time here
Write-Host "Hora asignación inicio: $startTime"
Write-Host "Hora asignación fin: $endTime"
$rolId = (Get-AzRoleDefinition -Name $rol).Id
$Justification = "Asignación de rol temporal por medio de Plantilla ITSM Automatizada"

New-AzRoleAssignmentScheduleRequest -Name $guid -Scope "/subscriptions/$IdSuscripcion/resourceGroups/$rg" -ExpirationType AfterDateTime -PrincipalId $idsp -RequestType AdminAssign -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" -ScheduleInfoStartDateTime $startTime -ExpirationEndDateTime  $endTime -Justification $Justification 

Write-Host "Se agrego el rol '$rol' correspondiente al service principal '$sp' en el grupo de recursos '$rg' de manera temporal"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' temporal de manera exitosa en el grupo de recursos '$rg' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm:ss')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm:ss')) )"

}
}catch {
    # Manejo de errores
    Write-Host "Error: $_"
    $body = $_.Exception.Message
    $statusCode = [HttpStatusCode]::BadRequest
}

# Respuesta HTTP
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
})
