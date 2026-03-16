function Format-ByteSize {
    <#
    .SYNOPSIS
        Formats byte count as human-readable size string.
    .DESCRIPTION
        Converts bytes to appropriate unit (B, KB, MB, GB, TB, PB) with specified decimal places.
    .PARAMETER Bytes
        The number of bytes to format.
    .PARAMETER Decimals
        Number of decimal places to display (default: 2).
    .EXAMPLE
        Format-ByteSize -Bytes 1073741824
        Returns: "1.00 GB"
    .EXAMPLE
        Format-ByteSize -Bytes 1536 -Decimals 1
        Returns: "1.5 KB"
    #>
    param (
        [long]$Bytes,
        [int]$Decimals = 2
    )

    if ($Bytes -eq 0) { return "0 B" }

    $sizes = @("B", "KB", "MB", "GB", "TB", "PB")
    $order = 0
    $size = [double]$Bytes

    while ($size -ge 1024 -and $order -lt $sizes.Count - 1) {
        $order++
        $size /= 1024
    }

    $format = "{0:N$Decimals} {1}"
    [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, $format, $size, $sizes[$order])
}
