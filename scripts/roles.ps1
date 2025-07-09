# Azure Role Assignment Script
# Requiere: Az PowerShell Module

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
    
    # 4. Configurar según el ámbito seleccionado
    switch ($selectedScope) {
        "Management Group" {
            $mgName = Read-Host "`nNombre del Management Group"
            $roleName = Read-Host "Nombre del Rol"
            $scopePath = "/providers/Microsoft.Management/managementGroups/$mgName"
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
        }
        
        "Resource Group" {
            $subscriptionName = Read-Host "`nNombre de la Suscripción"
            $rgName = Read-Host "Nombre del Resource Group"
            $roleName = Read-Host "Nombre del Rol"
            
            # Obtener subscription ID
            $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
            if (-not $subscription) {
                Write-Error "Suscripción '$subscriptionName' no encontrada"
                return
            }
            $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$rgName"
        }
        
        "Resource" {
            $subscriptionName = Read-Host "`nNombre de la Suscripción"
            $rgName = Read-Host "Nombre del Resource Group"
            $resourceType = Read-Host "Tipo de Recurso (ej: Microsoft.Storage/storageAccounts)"
            $resourceName = Read-Host "Nombre del Recurso"
            $roleName = Read-Host "Nombre del Rol"
            
            # Obtener subscription ID
            $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
            if (-not $subscription) {
                Write-Error "Suscripción '$subscriptionName' no encontrada"
                return
            }
            $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$rgName/providers/$resourceType/$resourceName"
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