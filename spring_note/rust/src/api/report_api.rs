use crate::report_regeneration::{self, RegenerateReportRequest, RegenerateReportResult};

pub async fn regenerate_report(request: RegenerateReportRequest) -> RegenerateReportResult {
    report_regeneration::regenerate_report(request).await
}
