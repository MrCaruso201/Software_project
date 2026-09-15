import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi import HTTPException
from services import pdf_router


class PDFBrowserTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        directory_patch = patch.object(pdf_router, "PDF_DIR", Path(directory.name))
        directory_patch.start()
        self.addCleanup(directory_patch.stop)

    async def publish(self, data):
        class Request:
            async def stream(self):
                yield data
        return await pdf_router.publish_pdf(Request(), {"id": 1})

    async def test_publish_and_open(self):
        data = b"%PDF-1.4\n%%EOF"
        result = await self.publish(data)
        response = pdf_router.view_pdf(result["path"].split("/")[-1])
        self.assertEqual(response.body, data)
        self.assertEqual(response.headers["content-type"], "application/pdf")
        self.assertTrue(response.headers["content-disposition"].startswith("inline;"))
        self.assertEqual(response.headers["cache-control"], "no-store")

    async def test_expiry(self):
        result = await self.publish(b"%PDF-1.4")
        with patch.object(pdf_router.time, "time", return_value=time.time() + 3601):
            with self.assertRaises(HTTPException) as error:
                pdf_router.view_pdf(result["path"].split("/")[-1])
        self.assertEqual(error.exception.status_code, 410)

    async def test_validation(self):
        with self.assertRaises(HTTPException) as error:
            await self.publish(b"hello")
        self.assertEqual(error.exception.status_code, 400)
        with patch.object(pdf_router, "MAX_BYTES", 5):
            with self.assertRaises(HTTPException) as error:
                await self.publish(b"%PDF-1.4")
        self.assertEqual(error.exception.status_code, 413)

    def test_unknown_link(self):
        with self.assertRaises(HTTPException) as error:
            pdf_router.view_pdf("missing.pdf")
        self.assertEqual(error.exception.status_code, 404)
