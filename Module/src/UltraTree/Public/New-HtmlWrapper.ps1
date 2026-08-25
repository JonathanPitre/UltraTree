function New-HtmlWrapper {
    <#
    .SYNOPSIS
        Wraps HTML fragment with full document including CSS/JS dependencies.
    .DESCRIPTION
        Use for local testing - NinjaOne WYSIWYG fields already have these loaded.
        Supports pipeline input from ConvertTo-NinjaOneHtml.
    .PARAMETER Content
        The HTML content to wrap. Accepts pipeline input.
    .PARAMETER Title
        The page title (default: "TreeSize Report").
    .EXAMPLE
        $html = Get-FolderSizes -DriveLetter C | ConvertTo-NinjaOneHtml
        $wrapped = New-HtmlWrapper -Content $html -Title "C: Drive Report"
    .EXAMPLE
        Get-FolderSizes -AllDrives | ConvertTo-NinjaOneHtml | New-HtmlWrapper | Out-File "report.html"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(ValueFromPipeline)]
        [string]$Content,
        [string]$Title = "TreeSize Report"
    )

    process {
        @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome 6 -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.2/css/all.min.css" rel="stylesheet">
    <!-- Charts.css -->
    <link href="https://cdn.jsdelivr.net/npm/charts.css/dist/charts.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f5f7fa;
            color: #333;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            padding: 20px;
        }
        .card {
            background-color: #fff;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            margin-bottom: 16px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.08);
        }
        .card-title-box {
            background-color: #f8f9fa;
            padding: 12px 16px;
            border-radius: 8px 8px 0 0;
            border-bottom: 1px solid #e0e0e0;
        }
        .card-title {
            color: #333;
            font-weight: 600;
            font-size: 1rem;
            margin: 0;
        }
        .card-body {
            padding: 16px;
        }
        .stat-card {
            text-align: center;
            padding: 20px;
            background-color: #fff;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            margin-bottom: 16px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.08);
        }
        .stat-value {
            font-size: 1.8rem;
            font-weight: 700;
            margin-bottom: 4px;
        }
        .stat-desc {
            font-size: 0.85rem;
            color: #666;
        }
        .info-card {
            background-color: #f8f9fa;
            border-left: 4px solid #5bc0de;
            padding: 12px 16px;
            margin-bottom: 12px;
            border-radius: 0 8px 8px 0;
        }
        .info-card.warning {
            border-left-color: #f0ad4e;
            background-color: #fff8e6;
        }
        .info-card.danger {
            border-left-color: #d9534f;
            background-color: #fef2f2;
        }
        .info-card-title {
            font-weight: 600;
            margin-bottom: 4px;
            color: #333;
        }
        .info-card-desc {
            font-size: 0.85rem;
            color: #666;
        }
        .tag {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 600;
            background-color: #4ECDC4;
            color: #fff;
        }
        .tag.expired, .tag.danger {
            background-color: #d9534f;
            color: white;
        }
        .tag.disabled, .tag.warning {
            background-color: #f0ad4e;
            color: white;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th {
            background-color: #f8f9fa;
            padding: 10px 12px;
            text-align: left;
            font-weight: 600;
            font-size: 0.85rem;
            color: #333;
            border-bottom: 2px solid #e0e0e0;
        }
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #e9ecef;
            font-size: 0.85rem;
        }
        tr:hover {
            background-color: #f8f9fa;
        }
        /* Charts.css customization */
        .charts-css.bar {
            --color: #337ab7;
            height: 200px;
            max-width: 100%;
        }
        .charts-css tbody tr {
            background-color: transparent;
        }
        .charts-css tbody tr:hover {
            background-color: transparent;
        }
        .charts-css td {
            border: none;
            padding: 0;
        }
        .charts-css th {
            background-color: transparent;
            padding: 4px 8px;
            font-size: 0.75rem;
            color: #666;
        }
        .progress {
            background-color: #e9ecef;
            border-radius: 4px;
            height: 8px;
        }
        .progress-bar {
            border-radius: 4px;
        }
        a {
            color: #337ab7;
        }
        a:hover {
            color: #23527c;
        }
        .flex-grow-1 {
            flex-grow: 1;
        }
        .d-flex {
            display: flex;
        }
    </style>
</head>
<body>
    <div class="container-fluid">
        $Content
    </div>
    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
"@
    }
}
